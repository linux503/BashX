#!/usr/bin/env bash
# Generate iOS alternate app icons from LogoStyle (Mac-only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$ROOT/build"
swiftc -sdk "$SDK" -framework AppKit -framework SwiftUI -framework CoreGraphics \
  -D ALT_ICON_GEN \
  "$ROOT/BashX/Services/LogoStyle.swift" \
  "$ROOT/scripts/ios_alt_icon_gen.swift" \
  -o "$ROOT/build/ios_alt_icon_gen"
"$ROOT/build/ios_alt_icon_gen" "$ROOT"
