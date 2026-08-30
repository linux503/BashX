#!/usr/bin/env bash
# Build universal BashX Release DMG for sharing to other Macs.
#
# With Developer ID Application + notary profile:
#   NOTARY_PROFILE=BashX-Notary ./scripts/build_dmg.sh
#   → signed + notarized (double-click open on other Macs)
#
# Without Developer ID (current machine):
#   → ad-hoc sign + 「一键解锁并打开」助手（其他电脑首次需右键打开助手一次）
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
  echo "  Mode: ad-hoc（其他电脑需用 DMG 内「一键解锁」；要免此步骤请在 Xcode 创建 Developer ID 证书）"
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

echo "[4/6] Install helper + 说明…"
# AppleScript .app — one-click install (copy + quarantine + icon cache + launch).
HELPER_SCRIPT="$STAGE/_install.applescript"
cat > "$HELPER_SCRIPT" <<'APPLESCRIPT'
on run
  set appsPath to "/Applications/BashX.app"
  set myPOSIX to POSIX path of (path to me)
  set parentPOSIX to do shell script "dirname " & quoted form of myPOSIX
  set dmgApp to parentPOSIX & "/BashX.app"

  try
    do shell script "mkdir -p /Applications"
  end try

  if (do shell script "[ -d " & quoted form of dmgApp & " ] && echo 1 || echo 0") is "1" then
    try
      do shell script "osascript -e 'tell application \"BashX\" to quit' 2>/dev/null || true"
    end try
    do shell script "sleep 0.4"
    do shell script "rm -rf " & quoted form of appsPath & "; ditto " & quoted form of dmgApp & " " & quoted form of appsPath
  else if (do shell script "[ -d " & quoted form of appsPath & " ] && echo 1 || echo 0") is not "1" then
    display dialog "未找到 BashX.app。请确认 DMG 已打开，且本助手与 BashX 在同一窗口。" buttons {"好"} default button 1 with icon stop
    return
  end if

  -- Gatekeeper quarantine + Finder/Dock icon cache
  do shell script "xattr -cr " & quoted form of appsPath & " 2>/dev/null || true"
  do shell script "touch " & quoted form of appsPath
  do shell script "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f " & quoted form of appsPath & " 2>/dev/null || true"
  do shell script "killall Dock 2>/dev/null || true"

  try
    do shell script "open " & quoted form of appsPath
  end try

  display dialog "✅ BashX 已安装到「应用程序」

• 图标已刷新（黄底 X）
• 若仍提示无法打开：系统设置 → 隐私与安全性 → 仍要打开

也可手动把 BashX 拖到「应用程序」文件夹。" buttons {"好"} default button 1 with icon note
end run
APPLESCRIPT

osacompile -o "$STAGE/安装 BashX.app" "$HELPER_SCRIPT" >/dev/null
rm -f "$HELPER_SCRIPT"
codesign --force --deep --sign - "$STAGE/安装 BashX.app" 2>/dev/null || true

cat > "$STAGE/使用说明.txt" <<EOF
BashX ${VERSION} — 安装说明
══════════════════════════════════════

【推荐】双击「安装 BashX」
  → 自动复制到应用程序、解除隔离、刷新 Dock 图标并启动

【或】把 BashX 拖到右侧「Applications」文件夹
  → 首次若打不开，再双击「安装 BashX」

──────────────────────────────────────
提示「已损坏 / 无法打开」？
  系统设置 → 隐私与安全性 → 仍要打开
  或终端：xattr -cr /Applications/BashX.app
EOF

# Legacy helper name (same script) for old docs / muscle memory.
ditto "$STAGE/安装 BashX.app" "$STAGE/一键解锁并打开.app"
codesign --force --deep --sign - "$STAGE/一键解锁并打开.app" 2>/dev/null || true

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
if [[ "$USE_DEV_ID" -eq 1 && -n "$NOTARY_PROFILE" ]]; then
  echo "发给别人后应可直接打开。"
else
  echo "发给别人时请说明：右键「一键解锁并打开」→ 打开。"
  echo "要彻底免此步骤：Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
fi
