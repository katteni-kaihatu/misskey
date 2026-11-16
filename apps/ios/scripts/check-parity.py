#!/usr/bin/env python3
# SPDX-FileCopyrightText: syuilo and misskey-project
# SPDX-License-Identifier: AGPL-3.0-only

"""Build and run opt-in native tests using a private local-parity run.json."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run-dir", type=Path, required=True)
parser.add_argument("--only-test", action="append", default=[])
parser.add_argument("--skip-project-generation", action="store_true", help="Reuse an already generated project; avoid concurrent XcodeGen writes")
parser.add_argument("--verify-export", action="store_true", help="Require and verify an archive saved through the native Files UI")
parser.add_argument("--verify-recovery", action="store_true", help="Require saved restored-data and recovery archives and verify their Blob contents")
args = parser.parse_args()
os.umask(0o077)
ios = Path(__file__).resolve().parents[1]
repository = ios.parents[1]
run_dir = args.run_dir.resolve()
if run_dir.is_relative_to(repository):
    parser.error("Keep test credentials and results outside the checkout")
if not (run_dir / "run.json").is_file():
    parser.error("Wait for LOCAL_PARITY_READY from local-parity-server.mjs")
run = json.loads((run_dir / "run.json").read_text())
environment = run["environment"]
if not isinstance(environment, dict) or not all(isinstance(k, str) and k.startswith("GRIDSPACE_PARITY_") and isinstance(v, str) for k, v in environment.items()):
    parser.error("Invalid fixture environment")
fixture_base = "ParityFixtures-" + str(uuid.UUID(run["snapshotID"]))
if run["fixtureDirectory"] != fixture_base:
    parser.error("Unexpected fixture directory")
# Every invocation owns a fresh destination, so a stale export cannot satisfy
# verification, and saving never overwrites a previous test's file.
# Keep the native Files caption short while retaining a fresh per-run folder.
fixture_name = "Parity-" + uuid.uuid4().hex[:12]
environment["GRIDSPACE_PARITY_FIXTURE_FOLDER"] = fixture_name
recovery_name = "Recover-" + uuid.uuid4().hex[:12]
environment["GRIDSPACE_PARITY_RECOVERY_FOLDER"] = recovery_name
migration_test = "GridSpaceUITests/LocalPWAParityTests/testPasswordLoginAndPersistentRestart"
recovery_test = "GridSpaceUITests/LocalPWAParityTests/testBlobRecoveryRestoresValuesAndExportsRecord"


def includes(test_name):
    return not args.only_test or any(test_name == value or test_name.startswith(value.rstrip("/") + "/") for value in args.only_test)


includes_migration = includes(migration_test)
includes_recovery = includes(recovery_test)
if args.verify_export and not includes_migration:
    parser.error("--verify-export requires the migration UI test")
if args.verify_recovery and not includes_recovery:
    parser.error("--verify-recovery requires the Blob recovery UI test")
fixtures = []
if includes_migration:
    fixtures.append(("migration", fixture_name, "parity-import.gridspace-localdata"))
if includes_recovery:
    fixtures.append(("recovery", recovery_name, "parity-recovery-expected.gridspace-localdata"))
for _, _, reference in fixtures:
    if not (run_dir / reference).is_file():
        parser.error("The selected fixture is missing; restart the private parity server")
device = os.environ.get("IOS_DEVICE")
simulator = os.environ.get("IOS_SIMULATOR")
if bool(device) == bool(simulator):
    parser.error("Set exactly one of IOS_DEVICE or IOS_SIMULATOR")
if simulator and "GRIDSPACE_PARITY_PROXY_ADDRESS" in environment:
    environment["GRIDSPACE_PARITY_PROXY_ADDRESS"] = "127.0.0.1"
destination = "id=" + device if device else "platform=iOS Simulator,id=" + simulator
derived = run_dir / "DerivedData"
build = ["xcodebuild", "-project", str(ios / "GridSpace.xcodeproj"), "-scheme", "GridSpace", "-configuration", "Debug",
         "-destination", destination, "-derivedDataPath", str(derived), "-parallel-testing-enabled", "NO"]
if device:
    team = os.environ.get("IOS_DEVELOPMENT_TEAM")
    if not team:
        parser.error("Set IOS_DEVELOPMENT_TEAM for a physical device")
    build += ["DEVELOPMENT_TEAM=" + team, "-allowProvisioningUpdates"]
else:
    build += ["CODE_SIGNING_ALLOWED=NO"]
if args.skip_project_generation:
    if not (ios / "GridSpace.xcodeproj" / "project.pbxproj").is_file():
        parser.error("Generate the Xcode project before --skip-project-generation")
else:
    subprocess.run(["xcodegen", "generate", "--spec", "project.yml"], cwd=ios, check=True)
subprocess.run(build + ["build-for-testing"], check=True)
products = derived / "Build" / "Products"
configuration = "Debug-iphoneos" if device else "Debug-iphonesimulator"
app = products / configuration / "GridSpace.app"
ui_runner = products / configuration / "GridSpaceUITests-Runner.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
if not all(info.get(key) is True for key in ["UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"]):
    parser.error("The Debug app must expose the synthetic Files fixture directory")
for _, name, reference in fixtures:
    fixture = run_dir / name
    fixture.mkdir(exist_ok=True)
    shutil.copyfile(run_dir / reference, fixture / reference)
if device:
    subprocess.run(["xcrun", "devicectl", "device", "install", "app", "--device", device, str(app)], check=True)
    for _, name, _ in fixtures:
        subprocess.run(["xcrun", "devicectl", "device", "copy", "to", "--device", device, "--source", str(run_dir / name),
                        "--destination", "Documents/" + name, "--domain-type", "appDataContainer", "--domain-identifier", "dev.gridspace.ios"], check=True)
else:
    subprocess.run(["xcrun", "simctl", "install", simulator, str(app)], check=True)
    # Replace only the synthetic runner, preserving the real app's data.
    # Unsigned UI bundles can otherwise be reused during repeated local runs.
    subprocess.run(["xcrun", "simctl", "uninstall", simulator, "dev.gridspace.ios.uitests.xctrunner"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "install", simulator, str(ui_runner)], check=True)
    if fixtures:
        container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", simulator, "dev.gridspace.ios", "data"], text=True).strip())
        for _, name, _ in fixtures:
            shutil.copytree(run_dir / name, container / "Documents" / name, dirs_exist_ok=True)
pattern = "GridSpace_iphoneos*.xctestrun" if device else "GridSpace_iphonesimulator*.xctestrun"
source = max(products.glob(pattern), key=lambda path: path.stat().st_mtime)
parameters = plistlib.loads(source.read_bytes())


def configure(value):
    if isinstance(value, str):
        return value.replace("__TESTROOT__", str(products))
    if isinstance(value, list):
        return [configure(item) for item in value]
    if isinstance(value, dict):
        result = {key: configure(item) for key, item in value.items()}
        if result.get("BlueprintName") in {"GridSpaceTests", "GridSpaceUITests"}:
            result.setdefault("EnvironmentVariables", {}).update(environment)
            result["UserAttachmentLifetime"] = "keepAlways"
        return result
    return value


settings = run_dir / "native.xctestrun"
settings.write_bytes(plistlib.dumps(configure(parameters)))
result = run_dir / ("result-" + uuid.uuid4().hex + ".xcresult")
test = ["xcodebuild", "test-without-building", "-xctestrun", str(settings), "-destination", destination,
        "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result)]
test += ["-only-testing:" + item for item in args.only_test]
completed = subprocess.run(test)
try:
    for kind, name, _ in fixtures if completed.returncode == 0 else []:
        copied = run_dir / "artifacts" / name
        copied.parent.mkdir(exist_ok=True)
        if device:
            subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", device,
                            "--source", "Documents/" + name, "--destination", str(copied),
                            "--domain-type", "appDataContainer", "--domain-identifier", "dev.gridspace.ios"], check=True)
        else:
            # Xcode may reinstall the app into a new sandbox during the test run.
            container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", simulator, "dev.gridspace.ios", "data"], text=True).strip())
            shutil.copytree(container / "Documents" / name, copied)
        exports = list(copied.glob("gridspace-*.gridspace-localdata"))
        recoveries = list(copied.glob("gridspace-*.gridspace-recovery"))
        if kind == "recovery" and len(exports) == 1 and len(recoveries) == 1:
            subprocess.run(["pnpm", "--filter", "frontend", "exec", "tsx", str(ios / "scripts/verify-recovery-export.mjs"),
                            str(copied), str(exports[0]), str(recoveries[0])], cwd=repository, check=True)
        elif kind == "migration" and len(exports) == 1:
            subprocess.run(["pnpm", "--filter", "frontend", "exec", "tsx", str(ios / "scripts/verify-parity-export.mjs"),
                            str(copied), str(exports[0])], cwd=repository, check=True)
        elif (args.verify_export if kind == "migration" else args.verify_recovery) or exports or recoveries:
            raise SystemExit("Expected the newly saved native archives for " + kind)
        else:
            print("SKIPPED: no native export (the Files scenario requires iOS 18.4 or later)", flush=True)
finally:
    # Restore normal device launch even when post-test artifact verification fails.
    if device and completed.returncode == 0:
        subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--device", device,
                        "--terminate-existing", "dev.gridspace.ios"], check=True)
raise SystemExit(completed.returncode)
