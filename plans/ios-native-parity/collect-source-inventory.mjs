#!/usr/bin/env node
/*
 * SPDX-FileCopyrightText: 2026 Misskey contributors
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Static catalog extractor. It never evaluates application code or changes app
// sources; it writes only the explicit output path. Requires TypeScript locally.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
function option(name, fallback = undefined) {
  const position = args.indexOf(name);
  if (position < 0) return fallback;
  if (!args[position + 1]) throw new Error(`${name} requires a value`);
  return args[position + 1];
}
if (args.includes('--help')) {
  process.stdout.write('Usage: node collect-source-inventory.mjs --root <checkout> [--output <json-file>]\n');
  process.exit(0);
}
const root = path.resolve(option('--root', process.cwd()));
const output = option('--output');
const require = createRequire(path.join(root, 'package.json'));
const ts = require('typescript');
const hashes = new Map();
const warnings = [];

function load(relativePath) {
  const text = fs.readFileSync(path.join(root, relativePath), 'utf8');
  hashes.set(relativePath, crypto.createHash('sha256').update(text).digest('hex'));
  const ast = ts.createSourceFile(relativePath, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  return { text, ast, relativePath };
}
function unwrap(node) {
  while (node && (ts.isAsExpression(node) || ts.isSatisfiesExpression(node) || ts.isParenthesizedExpression(node))) node = node.expression;
  return node;
}
function nameOf(node) {
  return ts.isIdentifier(node) || ts.isStringLiteralLike(node) || ts.isNumericLiteral(node) ? node.text : node.getText();
}
function literal(node) {
  node = unwrap(node);
  return node && ts.isStringLiteralLike(node) ? node.text : null;
}
function location(source, node) {
  return { file: source.relativePath, line: source.ast.getLineAndCharacterOfPosition(node.getStart(source.ast)).line + 1 };
}
function variables(source) {
  const result = new Map();
  function visit(node) {
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) result.set(node.name.text, unwrap(node.initializer));
    ts.forEachChild(node, visit);
  }
  visit(source.ast);
  return result;
}
function objectProperties(node) {
  node = unwrap(node);
  if (!node || !ts.isObjectLiteralExpression(node)) throw new Error('Expected object literal');
  return node.properties.filter(ts.isPropertyAssignment);
}
function property(node, key) {
  return objectProperties(node).find(p => nameOf(p.name) === key)?.initializer;
}
function findObject(node) {
  node = unwrap(node);
  if (ts.isObjectLiteralExpression(node)) return node;
  if (ts.isCallExpression(node) || ts.isNewExpression(node)) {
    for (const arg of node.arguments ?? []) {
      try { return findObject(arg); } catch { /* inspect the next argument */ }
    }
  }
  throw new Error('Object literal not found in initializer');
}
function expressions(node, source) {
  const values = {};
  for (const p of objectProperties(node)) values[nameOf(p.name)] = p.initializer.getText(source.ast);
  return values;
}
function componentPaths(node, source) {
  const result = new Set();
  const imports = new Map();
  function normalizeComponentPath(value) {
    if (value.startsWith('@/')) return value.replace(/^@\//, 'packages/frontend/src/');
    if (value.startsWith('./') || value.startsWith('../')) return path.posix.normalize(path.posix.join(path.posix.dirname(source.relativePath), value));
    return value;
  }
  for (const statement of source.ast.statements) {
    if (!ts.isImportDeclaration(statement) || !statement.importClause || !ts.isStringLiteralLike(statement.moduleSpecifier)) continue;
    if (statement.importClause.name) imports.set(statement.importClause.name.text, statement.moduleSpecifier.text);
  }
  function visit(child) {
    if (ts.isStringLiteralLike(child) && child.text.endsWith('.vue')) result.add(normalizeComponentPath(child.text));
    if (ts.isIdentifier(child) && imports.has(child.text)) result.add(normalizeComponentPath(imports.get(child.text)));
    ts.forEachChild(child, visit);
  }
  if (node) visit(node);
  return [...result].sort();
}

const routeSource = load('packages/frontend/src/router.definition.ts');
const routeRoot = variables(routeSource).get('ROUTE_DEF');
const routes = [];
function collectRoutes(arrayNode, parent = '', inheritedLogin = null, parentIndex = null) {
  arrayNode = unwrap(arrayNode);
  if (!ts.isArrayLiteralExpression(arrayNode)) throw new Error('ROUTE_DEF or children must be a static array');
  for (const raw of arrayNode.elements) {
    const node = unwrap(raw);
    if (!ts.isObjectLiteralExpression(node)) throw new Error(`Unsupported dynamic route at ${raw.getText()}`);
    const pathNode = property(node, 'path');
    const declaredPath = literal(pathNode);
    if (declaredPath === null) throw new Error(`Route path must be static: ${pathNode?.getText()}`);
    const props = expressions(node, routeSource);
    const login = props.loginRequired === 'true' ? true : props.loginRequired === 'false' ? false : inheritedLogin;
    const index = routes.length;
    routes.push({
      id: `route-${String(index + 1).padStart(3, '0')}`,
      path: parent + declaredPath,
      declaredPath,
      parentId: parentIndex === null ? null : `route-${String(parentIndex + 1).padStart(3, '0')}`,
      ...location(routeSource, pathNode),
      componentPaths: componentPaths(property(node, 'component'), routeSource),
      componentExpression: props.component ?? null,
      name: literal(property(node, 'name')),
      loginRequired: login,
      loginRequiredExpression: props.loginRequired ?? null,
      redirectExpression: props.redirect ?? null,
      queryExpression: props.query ?? null,
      hashExpression: props.hash ?? null,
      hasChildren: Boolean(property(node, 'children')),
    });
    const children = property(node, 'children');
    if (children) collectRoutes(children, parent + declaredPath, login, index);
  }
}
collectRoutes(routeRoot);

const prefSource = load('packages/frontend/src/preferences/def.ts');
const prefObject = findObject(variables(prefSource).get('PREF_DEF'));
const preferences = objectProperties(prefObject).map(p => ({
  key: nameOf(p.name), ...location(prefSource, p),
  ...expressions(p.initializer, prefSource),
}));

const storeSource = load('packages/frontend/src/store.ts');
const storeObject = findObject(variables(storeSource).get('store'));
const store = objectProperties(storeObject).map(p => ({
  key: nameOf(p.name), ...location(storeSource, p),
  ...expressions(p.initializer, storeSource),
}));

const widgetSource = load('packages/frontend/src/widgets/index.ts');
const widgetVariables = variables(widgetSource);
function arrayStrings(node, seen = new Set()) {
  node = unwrap(node);
  if (ts.isIdentifier(node)) {
    if (seen.has(node.text)) throw new Error(`Circular array: ${node.text}`);
    return arrayStrings(widgetVariables.get(node.text), new Set([...seen, node.text]));
  }
  if (!node || !ts.isArrayLiteralExpression(node)) throw new Error('Widget arrays must be static');
  return node.elements.flatMap(item => {
    if (ts.isSpreadElement(item)) return arrayStrings(item.expression, seen);
    const value = literal(item);
    if (value === null) throw new Error(`Unsupported widget expression: ${item.getText()}`);
    return [{ id: value, ...location(widgetSource, item) }];
  });
}
const registrations = [];
function collectRegistrations(node) {
  if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && node.expression.name.text === 'component') {
    const name = literal(node.arguments[0]);
    if (name) registrations.push({ name, componentPaths: componentPaths(node.arguments[1], widgetSource), ...location(widgetSource, node) });
  }
  ts.forEachChild(node, collectRegistrations);
}
collectRegistrations(widgetSource.ast);
const federatedIds = new Set(arrayStrings(widgetVariables.get('federationWidgets')).map(item => item.id));
const widgets = arrayStrings(widgetVariables.get('widgets')).map(item => {
  const registration = registrations.find(entry => entry.name.toLowerCase() === `widget${item.id}`.toLowerCase());
  if (!registration) warnings.push(`No registration found for ${item.id}`);
  return { ...item, federationOnly: federatedIds.has(item.id), registration: registration ?? null };
});

const navbarSource = load('packages/frontend/src/navbar.ts');
const navbarObject = findObject(variables(navbarSource).get('navbarItemDef'));
const navbar = objectProperties(navbarObject).map(p => ({ key: nameOf(p.name), ...location(navbarSource, p), ...expressions(p.initializer, navbarSource) }));

function walk(relativeDir) {
  return fs.readdirSync(path.join(root, relativeDir), { withFileTypes: true }).flatMap(entry => {
    const relative = `${relativeDir}/${entry.name}`;
    return entry.isDirectory() ? walk(relative) : [relative];
  }).sort();
}
const pages = walk('packages/frontend/src/pages')
  .filter(file => file.endsWith('.vue') && !/\.(?:test|spec|stories(?:\.impl)?)\./.test(file))
  .map(file => {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    const sha256 = crypto.createHash('sha256').update(text).digest('hex');
    const directlyReferencedBy = routes.filter(route => route.componentPaths.includes(file)).map(route => route.id);
    return { file, sha256, directlyReferencedBy, role: directlyReferencedBy.length ? 'route-component' : 'nested-or-dynamically-referenced-component' };
  });

const bootSource = load('packages/frontend/src/_boot_.ts');
const specialBootPathsNode = variables(bootSource).get('subBootPaths');
const specialBootPaths = unwrap(specialBootPathsNode).elements.map(node => ({ path: literal(node), ...location(bootSource, node) }));

const metadata = {
  formatVersion: 1,
  checkoutCommit: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(),
  packageVersion: JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version,
  methods: {
    routes: 'TypeScript AST: ROUTE_DEF static array; parent + child path concatenation matches Nirax; dynamic expressions preserved without executing them',
    preferences: 'TypeScript AST: direct property assignments in definePreferences(PREF_DEF)',
    store: 'TypeScript AST: direct property assignments in new Pizzax(base, object)',
    widgets: 'TypeScript AST: widgets array plus recursively expanded local array spreads; app.component registrations',
    navbar: 'TypeScript AST: direct property assignments in reactive(navbarItemDef)',
    pages: 'Recursive .vue file walk under pages, excluding test/spec/stories names; classify direct route references without claiming unreferenced files are unreachable',
  },
  limitations: [
    'Static catalogs establish discovery coverage, not runtime behavior, entitlement availability, or native/WebView compatibility.',
    'Routes with identical full paths may represent shell and empty child declarations; both are intentionally retained.',
    'Component expressions preserve login/role-conditional alternatives; runtime feature flags and nested component actions require manual auditing.',
    'Direct property collection does not expand arbitrary object spreads. Current catalog structures are checked to have no such omitted entries.',
    'Preference and store defaults are source expressions, not evaluated values; all unknown future keys must remain preserved by migrations.',
    'A page without a direct route reference may be nested, dynamically loaded, or a helper; it is not classified as unused.',
  ],
  sourceHashes: [...hashes].map(([file, sha256]) => ({ file, sha256 })),
};
for (const [label, object] of [['preferences', prefObject], ['store', storeObject], ['navbar', navbarObject]]) {
  if (object.properties.some(p => !ts.isPropertyAssignment(p))) throw new Error(`Unsupported properties in ${label}; update the extractor before claiming coverage`);
}
const result = {
  metadata,
  counts: { routes: routes.length, uniqueFullPaths: new Set(routes.map(row => row.path)).size, preferences: preferences.length, store: store.length, widgets: widgets.length, navbar: navbar.length, pages: pages.length, specialBootPaths: specialBootPaths.length },
  routes, preferences, store, widgets, navbar, pages, specialBootPaths, warnings,
};
const serialized = JSON.stringify(result, null, 2) + '\n';
if (output) fs.writeFileSync(path.resolve(output), serialized);
else process.stdout.write(serialized);
