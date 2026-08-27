#!/usr/bin/env bash
# Build BashX Release and pack a DMG that opens cleanly on other Macs
# (ad-hoc sign + strip quarantine; include first-open helper).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BashX/Info.plist" 2>/dev/null || echo "0.1.1")"
BUILD_DIR="$ROOT/build-release"
APP="$BUILD_DIR/Build/Products/Release/BashX.app"
DIST="$ROOT/dist"
DMG="$DIST/BashX-${VERSION}.dmg"
STAGE="$DIST/dmg-stage"
SIGN_ID="${CODE_SIGN_IDENTITY:--}"

echo "== BashX DMG build v${VERSION} =="

cd "$ROOT"
if [[ -f project.yml ]]; then
  command -v xcodegen >/dev/null 2>&1 && xcodegen generate
fi

echo "[0/5] Fetch embedded mihomo cores…"
chmod +x "$ROOT/scripts/fetch_mihomo.sh"
"$ROOT/scripts/fetch_mihomo.sh"

echo "[1/5] Release build (universal)…"
# Prefer real identity if provided; otherwise leave unsigned then ad-hoc sign later.
# Do NOT ship completely unsigned — Gatekeeper shows “文件已损坏”.
xcodebuild \
  -project "$ROOT/BashX.xcodeproj" \
  -scheme BashX \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  build \
  CODE_SIGN_IDENTITY="${SIGN_ID}" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  | tail -30

[[ -d "$APP" ]] || { echo "Missing $APP"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/BashX-${VERSION}.dmg"
echo "  ✓ $APP (v${VERSION})"

echo "[2/5] Stage + strip quarantine…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# ditto preserves structure better than cp -R for .app bundles
ditto "$APP" "$STAGE/BashX.app"
ln -sf /Applications "$STAGE/Applications"

# Drop legacy uncompressed cores if gzip bundles are present.
CORE_RES="$STAGE/BashX.app/Contents/Resources/Core"
if [[ -d "$CORE_RES" ]]; then
  for gz in "$CORE_RES"/*.gz; do
    [[ -f "$gz" ]] || continue
    base="${gz%.gz}"
    [[ -f "$base" ]] && rm -f "$base"
  done
fi

# Strip debug symbols from shipped binaries (smaller on disk).
strip -x "$STAGE/BashX.app/Contents/MacOS/BashX" 2>/dev/null || true

# Remove ALL extended attributes (quarantine / resource forks break Gatekeeper)
xattr -cr "$STAGE/BashX.app" 2>/dev/null || true
find "$STAGE/BashX.app" -type f -exec xattr -c {} \; 2>/dev/null || true

echo "[3/5] Ad-hoc codesign (deep)…"
# Deep ad-hoc sign so other Macs don't get “文件已损坏” after clearing quarantine.
# Hardened runtime intentionally omitted — requires Developer ID + notarization.
codesign --force --deep --sign - \
  --timestamp=none \
  --entitlements "$ROOT/BashX/BashX.entitlements" \
  "$STAGE/BashX.app"

codesign --verify --deep --strict --verbose=2 "$STAGE/BashX.app" 2>&1 | tail -8 || {
  echo "WARN: codesign verify reported issues (continuing)"
}

# First-open helper for recipients who still hit Gatekeeper
cat > "$STAGE/首次打开（其他电脑必看）.command" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
APP="BashX.app"
if [[ ! -d "$APP" ]]; then
  osascript -e 'display dialog "未找到 BashX.app，请先把本 DMG 里的 BashX 拖到「应用程序」后再运行本脚本，或把脚本与 App 放在同一文件夹。" buttons {"好"} default button 1'
  exit 1
fi
# Clear Gatekeeper quarantine — this is why other Macs say “文件已损坏”
xattr -cr "$APP" 2>/dev/null || true
# Also clear if already copied to Applications
if [[ -d "/Applications/BashX.app" ]]; then
  xattr -cr "/Applications/BashX.app" 2>/dev/null || true
fi
open "$APP"
osascript -e 'display dialog "已移除隔离属性并尝试打开 BashX。\n\n若仍无法打开：系统设置 → 隐私与安全性 → 仍要打开。" buttons {"好"} default button 1' >/dev/null 2>&1 || true
EOF
chmod +x "$STAGE/首次打开（其他电脑必看）.command"

cat > "$STAGE/使用说明.txt" <<EOF
BashX ${VERSION}

【其他电脑打开提示「文件已损坏」时】
这是 macOS 安全机制（Gatekeeper），不是安装包真的坏了。

处理方式（任选其一）：
1. 双击 DMG 里的「首次打开（其他电脑必看）.command」，按提示允许
2. 或把 BashX.app 拖到「应用程序」后，打开「终端」执行：
   xattr -cr /Applications/BashX.app
   然后正常打开 BashX
3. 系统设置 → 隐私与安全性 → 仍要打开

推荐：先把 BashX 拖到「应用程序」，再运行「首次打开」脚本。
EOF

echo "[4/5] Create DMG…"
mkdir -p "$DIST"
# UDZO compressed; no internet-enable so Gatekeeper is less aggressive on the volume
hdiutil create \
  -volname "BashX" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG"

# Strip quarantine from the DMG itself (local copy)
xattr -c "$DMG" 2>/dev/null || true

echo "[5/5] Cleanup"
rm -rf "$STAGE"

echo ""
echo "Done: $DMG"
ls -lh "$DMG"
echo ""
echo "Tip: send this DMG; recipients who see「损坏」should run「首次打开」inside the DMG."
