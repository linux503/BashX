#!/usr/bin/env bash
# Install BashX to paired iPhones (USB or wireless). Unlock phones and trust this Mac first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build-ios/Build/Products/Release-iphoneos/BashX.app"

if [[ ! -d "$APP" ]]; then
  echo "Building Release for iOS..."
  xcodebuild -project "$ROOT/BashX.xcodeproj" -scheme BashXiOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$ROOT/build-ios" build
fi

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
echo "Installing BashX ${VER}"

install_one() {
  local name="$1" id="$2"
  echo "-> ${name} (${id})"
  if xcrun devicectl device install app --device "$id" "$APP"; then
    echo "  OK"
  else
    echo "  FAILED (unlock phone, enable Developer Mode, USB or same Wi-Fi)"
    return 1
  fi
}

FAILED=0
install_one "K iPhone Air" "1E7BC1EC-EAAF-56BB-80BF-D0F01663E89E" || FAILED=1
install_one "X iPhone 17 Pro Max" "CB30C5B0-C0D3-5E99-8CBA-8F1F5F1F98C0" || FAILED=1

if [[ "$FAILED" -eq 0 ]]; then
  echo "Done - both devices updated."
else
  echo "Some installs failed. Connect phones via USB, unlock, then re-run:"
  echo "  $0"
  exit 1
fi
