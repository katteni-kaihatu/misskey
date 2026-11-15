#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This check needs macOS with full Xcode selected." >&2
  exit 1
fi
command -v xcodegen >/dev/null || {
  echo "Install XcodeGen (brew install xcodegen), then retry." >&2
  exit 1
}
xcodebuild -version
swift test --package-path Core
xcodegen generate --spec project.yml
xcodebuild -project GridSpace.xcodeproj -scheme GridSpace \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

if [[ "${1:-}" == "--test" ]]; then
  : "${IOS_SIMULATOR:?Set IOS_SIMULATOR to a bootable simulator UDID from xcrun simctl list devices available}"
  xcodebuild -project GridSpace.xcodeproj -scheme GridSpace \
    -destination "platform=iOS Simulator,id=${IOS_SIMULATOR}" \
    -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
fi
