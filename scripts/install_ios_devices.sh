#!/usr/bin/env bash
# Install BashX to all paired physical iPhones (USB or wireless). Unlock phones and trust this Mac first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build-ios/Build/Products/Release-iphoneos/BashX.app"

if [[ ! -d "$APP" ]]; then
  NEED_BUILD=1
else
  BUILT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo '')"
  WANT_VER="$(grep 'MARKETING_VERSION:' "$ROOT/project.yml" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')"
  [[ "$BUILT_VER" != "$WANT_VER" ]] && NEED_BUILD=1 || NEED_BUILD=0
fi
if [[ "${NEED_BUILD:-1}" -eq 1 ]]; then
  echo "Building Release for iOS..."
  xcodebuild -project "$ROOT/BashX.xcodeproj" -scheme BashXiOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$ROOT/build-ios" build
fi

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
echo "Installing BashX ${VER}"

# devicectl: physical iPhone, paired + available (skip simulators / unavailable / shutdown)
DEVICES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DEVICES+=("$line")
done < <(
  xcrun devicectl list devices 2>/dev/null | python3 -c '
import re, sys
uuid = re.compile(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", re.I)
for line in sys.stdin:
    if "physical" not in line or "iPhone" not in line:
        continue
    if "unavailable" in line or "shutdown" in line:
        continue
    m = uuid.search(line)
    if not m:
        continue
    ident = m.group(0)
    name = line[: m.start()].strip()
    name = re.sub(r"\s{2,}.*$", "", name).strip() or ident
    print(f"{name}|{ident}")
'
)

if [[ "${#DEVICES[@]}" -eq 0 ]]; then
  echo "No paired iPhones found. Connect via USB, unlock, trust this Mac, enable Developer Mode."
  exit 1
fi

echo "Targets (${#DEVICES[@]}):"
for entry in "${DEVICES[@]}"; do
  echo "  - ${entry%%|*} (${entry##*|})"
done

FAILED=0
for entry in "${DEVICES[@]}"; do
  name="${entry%%|*}"
  id="${entry##*|}"
  echo "-> ${name} (${id})"
  if xcrun devicectl device install app --device "$id" "$APP"; then
    echo "  OK"
  else
    echo "  FAILED (unlock phone, enable Developer Mode, USB or same Wi-Fi)"
    FAILED=1
  fi
done

if [[ "$FAILED" -eq 0 ]]; then
  echo "Done — all ${#DEVICES[@]} device(s) updated."
else
  echo "Some installs failed. Unlock phones and re-run:"
  echo "  $0"
  exit 1
fi
