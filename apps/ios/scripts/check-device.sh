#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This check needs macOS with full Xcode selected." >&2
  exit 1
fi
mode="${1:-build}"
case "$mode" in
  build|--test|--install) ;;
  *) echo "Usage: check-device.sh [--test|--install]" >&2; exit 1 ;;
esac
association_domain="${IOS_AUTH_DOMAIN:-}"
if [[ -n "$association_domain" ]]; then
  if [[ ${#association_domain} -gt 253 || ! "$association_domain" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "IOS_AUTH_DOMAIN must be an exact DNS hostname, without a scheme, port, path, query or wildcard." >&2
    exit 1
  fi
  IFS='.' read -r -a association_labels <<< "$association_domain"
  for association_label in "${association_labels[@]}"; do
    if [[ ${#association_label} -gt 63 || "$association_label" == -* || "$association_label" == *- ]]; then
      echo "IOS_AUTH_DOMAIN contains an invalid DNS label." >&2
      exit 1
    fi
  done
  association_tld="${association_domain##*.}"
  if [[ ! "$association_tld" =~ ^[A-Za-z] ]]; then
    echo "IOS_AUTH_DOMAIN must be a DNS hostname, not an IP address." >&2
    exit 1
  fi
fi
: "${IOS_DEVICE:?Set IOS_DEVICE to a paired device identifier from xcrun devicectl list devices}"
: "${IOS_DEVELOPMENT_TEAM:?Set IOS_DEVELOPMENT_TEAM to your Apple Development team identifier}"
command -v xcodegen >/dev/null || {
  echo "Install XcodeGen (brew install xcodegen), then retry." >&2
  exit 1
}
xcodebuild -version
swift test --package-path Core
xcodegen generate --spec project.yml
action=build
if [[ "$mode" == "--test" ]]; then action=test; fi
configuration=Debug
# UI fixtures require DEBUG, while normal use needs Swift's optimized build.
if [[ "$mode" == "--install" ]]; then configuration=Release; fi
build_args=(-project GridSpace.xcodeproj -scheme GridSpace -configuration "$configuration"
  -destination "id=${IOS_DEVICE}" -derivedDataPath DerivedData
  "DEVELOPMENT_TEAM=${IOS_DEVELOPMENT_TEAM}" -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration -parallel-testing-enabled NO)
if [[ -n "$association_domain" ]]; then
  # Apply the entitlement path to the app target only, not test runners/frameworks.
  build_args+=("IOS_APPLICATION_ENTITLEMENTS=Configuration/AssociatedDomains.entitlements" "IOS_AUTH_DOMAIN=${association_domain}")
fi
xcodebuild "${build_args[@]}" "$action"

if [[ "$mode" == "--install" ]]; then
  xcrun devicectl device install app --device "$IOS_DEVICE" \
    "DerivedData/Build/Products/${configuration}-iphoneos/GridSpace.app"
  xcrun devicectl device process launch --device "$IOS_DEVICE" \
    --terminate-existing dev.gridspace.ios
fi
