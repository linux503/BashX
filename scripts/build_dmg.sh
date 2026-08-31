#!/usr/bin/env bash
# Build universal BashX Release DMG for sharing to other Macs.
#
# With Developer ID Application + notary profile:
#   NOTARY_PROFILE=BashX-Notary ./scripts/build_dmg.sh
#   → signed + notarized (double-click open on other Macs)
#
# Without Developer ID (current machine):
#   → ad-hoc sign + 「安装.command」（其他电脑首次需右键打开安装脚本）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BashX/Info.plist" 2>/dev/null || echo "0.1.1")"
BUILD_DIR="$ROOT/build-release"
APP="$BUILD_DIR/Build/Products/Release/BashX.app"
DIST="$ROOT/dist"
DMG="$DIST/BashX-${VERSION}.dmg"
STAGE="$DIST/dmg-stage"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "== BashX DMG build v${VERSION} =="

# Prefer Developer ID Application for distribution; else ad-hoc (-).
pick_sign_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "$CODE_SIGN_IDENTITY"
    return
  fi
  local id
  id="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi
  echo "-"
}

SIGN_ID="$(pick_sign_identity)"
USE_DEV_ID=0
if [[ "$SIGN_ID" == Developer\ ID\ Application* ]]; then
  USE_DEV_ID=1
fi
echo "  Sign identity: $SIGN_ID"
if [[ "$USE_DEV_ID" -eq 1 ]]; then
  echo "  Mode: Developer ID (can notarize)"
else
  echo "  Mode: ad-hoc（其他电脑用「安装.command」；要免此步骤请创建 Developer ID 证书）"
fi

cd "$ROOT"
if [[ -f project.yml ]]; then
  command -v xcodegen >/dev/null 2>&1 && xcodegen generate
fi

echo "[0/6] Regenerate brand icons + fetch mihomo cores…"
swift "$ROOT/scripts/generate_icons.swift"
chmod +x "$ROOT/scripts/fetch_mihomo.sh"
"$ROOT/scripts/fetch_mihomo.sh"

echo "[1/6] Release build (universal arm64+x86_64)…"
xcodebuild \
  -project "$ROOT/BashX.xcodeproj" \
  -scheme BashX \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  | tail -40

[[ -d "$APP" ]] || { echo "Missing $APP"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/BashX-${VERSION}.dmg"
echo "  ✓ $APP (v${VERSION})"
file "$APP/Contents/MacOS/BashX" || true
lipo -info "$APP/Contents/MacOS/BashX" 2>/dev/null || true

echo "[2/6] Stage + strip quarantine…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/BashX.app"
ln -sf /Applications "$STAGE/Applications"

CORE_RES="$STAGE/BashX.app/Contents/Resources/Core"
if [[ -d "$CORE_RES" ]]; then
  for gz in "$CORE_RES"/*.gz; do
    [[ -f "$gz" ]] || continue
    base="${gz%.gz}"
    [[ -f "$base" ]] && rm -f "$base"
  done
fi

# Strip only the main binary before (re)signing.
strip -x "$STAGE/BashX.app/Contents/MacOS/BashX" 2>/dev/null || true

xattr -cr "$STAGE/BashX.app" 2>/dev/null || true
find "$STAGE/BashX.app" -exec xattr -c {} \; 2>/dev/null || true

echo "[3/6] Codesign…"
ENTITLEMENTS="$ROOT/BashX/BashX.entitlements"
sign_one() {
  local path="$1"
  if [[ "$USE_DEV_ID" -eq 1 ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
      --entitlements "$ENTITLEMENTS" "$path" 2>/dev/null \
      || codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$path"
  else
    codesign --force --sign - --timestamp=none \
      --entitlements "$ENTITLEMENTS" "$path" 2>/dev/null \
      || codesign --force --sign - --timestamp=none "$path"
  fi
}

# Nested helper first, then app bundle.
if [[ -f "$STAGE/BashX.app/Contents/Resources/BashXTunHelper" ]]; then
  chmod +x "$STAGE/BashX.app/Contents/Resources/BashXTunHelper"
  sign_one "$STAGE/BashX.app/Contents/Resources/BashXTunHelper"
fi
if [[ -f "$STAGE/BashX.app/Contents/MacOS/BashXTunHelper" ]]; then
  chmod +x "$STAGE/BashX.app/Contents/MacOS/BashXTunHelper"
  sign_one "$STAGE/BashX.app/Contents/MacOS/BashXTunHelper"
fi

if [[ "$USE_DEV_ID" -eq 1 ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" \
    --entitlements "$ENTITLEMENTS" "$STAGE/BashX.app"
else
  codesign --force --deep --sign - --timestamp=none \
    --entitlements "$ENTITLEMENTS" "$STAGE/BashX.app"
fi

codesign --verify --deep --strict --verbose=2 "$STAGE/BashX.app" 2>&1 | tail -10 || {
  echo "WARN: codesign verify reported issues (continuing)"
}

echo "[4/6] Install helper…"
# DMG keeps only: BashX.app + Applications + 安装.command
cat > "$STAGE/安装.command" <<'UNLOCK'
#!/bin/bash
# BashX unlock + install (ad-hoc builds / Gatekeeper).
set -euo pipefail
cd "$(dirname "$0")"
SRC="$(pwd)/BashX.app"
DST="/Applications/BashX.app"

echo ""
echo "════════════════════════════════════"
echo "  BashX 安装"
echo "════════════════════════════════════"
echo ""

if [[ ! -d "$SRC" ]]; then
  echo "❌ 未找到 BashX.app，请先打开 DMG 再运行本脚本。"
  read -r -p "按回车关闭…" _
  exit 1
fi

osascript -e 'tell application "BashX" to quit' >/dev/null 2>&1 || true
sleep 0.4

echo "将请求管理员密码：复制到应用程序并清除隔离标记…"
sudo /bin/bash -c "
set -e
rm -rf '$DST'
/usr/bin/ditto '$SRC' '$DST'
/usr/bin/xattr -cr '$DST' 2>/dev/null || true
/usr/bin/find '$DST' -exec /usr/bin/xattr -c {} \; 2>/dev/null || true
/usr/bin/xattr -dr com.apple.quarantine '$DST' 2>/dev/null || true
/usr/bin/xattr -dr com.apple.provenance '$DST' 2>/dev/null || true
/usr/bin/xattr -dr com.apple.macl '$DST' 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - '$DST' 2>/dev/null || true
/usr/bin/touch '$DST'
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f '$DST' 2>/dev/null || true
echo OK
"

echo ""
echo "正在启动…"
if /usr/bin/open "$DST" 2>/dev/null; then
  echo "✅ 已安装并打开。"
else
  nohup "$DST/Contents/MacOS/BashX" >/tmp/bashx-launch.log 2>&1 &
  sleep 1
  if pgrep -x BashX >/dev/null 2>&1; then
    echo "✅ BashX 已在后台运行（看菜单栏图标）。"
  else
    echo "❌ 仍无法启动。终端粘贴："
    echo "   xattr -cr /Applications/BashX.app && open /Applications/BashX.app"
  fi
fi

echo ""
read -r -p "按回车关闭窗口…" _
UNLOCK
chmod +x "$STAGE/安装.command"
xattr -c "$STAGE/安装.command" 2>/dev/null || true

echo "[5/6] Create DMG…"
mkdir -p "$DIST"
hdiutil create \
  -volname "BashX" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG"

xattr -c "$DMG" 2>/dev/null || true

if [[ "$USE_DEV_ID" -eq 1 ]]; then
  echo "[6/6] Notarize DMG…"
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG" 2>/dev/null || true
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "  ✓ Notarized + stapled"
  else
    echo "  ⚠ Developer ID 已签名，但未设置 NOTARY_PROFILE，跳过公证。"
    echo "    一次配置: xcrun notarytool store-credentials BashX-Notary"
    echo "    然后: NOTARY_PROFILE=BashX-Notary ./scripts/build_dmg.sh"
  fi
else
  echo "[6/6] Skip notarization (no Developer ID)"
fi

rm -rf "$STAGE"

cp -f "$DMG" "$DIST/BashX.dmg"
echo "Stable latest: $DIST/BashX.dmg"

echo ""
echo "Done: $DMG"
ls -lh "$DMG"
echo ""
echo "  DMG 内容: BashX.app + Applications + 安装.command"
if [[ "$USE_DEV_ID" -eq 1 && -n "$NOTARY_PROFILE" ]]; then
  echo "发给别人后应可直接打开。"
else
  echo "发给别人时请说明：右键「安装.command」→ 打开（输入密码）。"
  echo "要彻底免此步骤：Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
fi
