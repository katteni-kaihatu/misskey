# GridSpace external reader API

This API supports the Even G2 reader and other text clients. It uses existing Misskey MiAuth application tokens. It does not require the user's native login token or expose peer credentials. All endpoints are POST requests under `/api/gridspace/client/` and return `Cache-Control: private, no-store`.

## Permissions

| Permission | Use |
| --- | --- |
| `read:account` | Query `status` |
| `read:gridspace-client-timeline` | Read the user's home timeline |
| `read:gridspace-client-notifications` | Read notifications without marking them read |
| `read:gridspace-client-private` | Opt in to peer timeline/notifications and their authorized private content |

Request the first three permissions for the initial reader. Request the private permission only when the user enables peer access. Application permission does not establish a GridSpace account link or grant access on the other server. Those authorizations remain in Misskey's existing GridSpace settings.

The first release deliberately uses local-only timeline sources unless `includePrivate: true` is requested and authorized. This avoids silently using the account's existing cross-server private grant. Public peer posts already present in the local timeline can still appear. Additional peer-source data, including channel placements owned by the peer, requires the private opt-in.

## Requests

Send `Authorization: Bearer <application-token>` and `Content-Type: application/json`. Misskey's existing `i` body parameter is also supported. Do not put tokens in query strings, logs, app packages or source control.

### `status`

Input: `{}`. Output fields: `version`, `timeline`, `notifications`, `peerPrivate`, `peer`. `peer` is `ok`, `disabled`, `unauthorized`, or `unavailable`. No account-link secrets or authorization URLs are returned.

### `timeline`

Input:

```json
{ "limit": 20, "includePrivate": false }
```

`limit` defaults to 20 and accepts 1–40. Supply `cursor` from `nextCursor` for the next page, preserving `includePrivate`. The timeline is always the authenticated user's home; user IDs, URLs and other internal timeline kinds are not client-selectable.

Output: `version`, `items`, `nextCursor`, `complete`, `sources`, `revalidateAfterMs`. Each item contains `key`, `note`, `validForMs`, and `nextPolicyCheckAt`. A note contains `id`, `uri`, `origin`, `createdAt`, `text`, `cw`, `visibility`, `author`, `fileCount`, and an optional one-level `renote` summary (or null). This projection does not expose internal session IDs, reference tokens, action capabilities or arbitrary packed-note fields.

The app formats text, CW and MFM for the glasses. A non-null CW should be presented before showing its body. File counts are supplied; full image delivery and write actions are outside this release.

### `notifications`

Input:

```json
{ "source": "local", "limit": 20, "includePrivate": false }
```

`source` is `local` (default), `peer`, or `channel`. Both `peer` and `channel` require `includePrivate: true` and the private permission, plus their existing server-side authorization. Pagination uses the returned `nextCursor` with the same source and private setting.

Output: `version`, `items`, `nextCursor`, `source`, `unreadCount`, `validForMs`, `revalidateAfterMs`. Items contain a stable `key`, `id`, `createdAt`, `type`, `isRead`, optional user/note summaries, `body` and `reaction`. Reading does not mark a notification read. A failed source returns no items, no cursor, and `unreadCount: null`, with `unauthorized` or `unavailable` status; it never replays cached content.

## Refresh and revocation

- Cursors expire after ten minutes and are bound to the user, application token, current permissions, relevant linked grant, source and private setting. Treat them as opaque.
- On `GRIDSPACE_CLIENT_INVALID_CURSOR`, discard the cursor and refresh from the first page. Do the same after changing permissions, switching accounts or restarting without valid state.
- Respect `revalidateAfterMs`. A refresh starts with no cursor; first-release APIs do not expose WebSocket subscriptions or incremental session handles.
- Clear protected content when its non-null `validForMs` expires, when `nextPolicyCheckAt` is reached, or when authorization/revalidation fails. Do not persist private content. Server revocation cannot erase content an application already downloaded.
- Account status and application permissions are reread before the response. Existing services still check block/mute rules, current visibility, linked-grant validity and peer authorization.
- Peer failures can leave a partial local timeline. Check `complete` and each source's `status` instead of interpreting an empty result as proof that no posts exist.
- Back off after HTTP 429 and transient failures. Do not run concurrent refresh loops while the app is suspended. G2 lock-screen behavior is tested separately in the app.

## Errors

Normal Misskey authentication, permission and parameter errors still apply. Reader-specific errors use the standard Misskey `error` object:

| Code | Meaning |
| --- | --- |
| `GRIDSPACE_CLIENT_APP_TOKEN_REQUIRED` | A native login token was supplied; use a MiAuth application token |
| `GRIDSPACE_CLIENT_PERMISSION_DENIED` | A required application permission is missing |
| `GRIDSPACE_CLIENT_AUTHORIZATION_REVOKED` | The token, account or linked authorization changed during the request |
| `GRIDSPACE_CLIENT_INVALID_CURSOR` | Cursor expired, was modified or belongs to another context |
| `GRIDSPACE_CLIENT_UNAVAILABLE` | The reader is disabled or temporarily unavailable |

For Even Hub, add only the server's HTTPS origin to the app's network permission whitelist. Validate CORS/preflight against that origin. This server release does not install or publish an Even Hub app.
