#!/usr/bin/env bash
# Build DMG, push git, create GitHub Release with versioned + BashX.dmg assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BashX/Info.plist")"
DMG="$ROOT/dist/BashX-${VERSION}.dmg"
STABLE="$ROOT/dist/BashX.dmg"
TAG="v${VERSION}"
RELEASES_PAGE="https://github.com/linux503/BashX/releases"
RELEASE_NOTES="$(cat <<'EOF'
## BashX 1.0.14

- Mac：移除面板「应用」分组页；菜单栏策略组改为打开面板
- Mac：修复线路策略选中后被自动切回手动的问题，并优化卡片展示
- Mac：修复节点测速按钮状态不刷新 / 一直灰的问题
- 完整 Clash YAML 订阅保留原策略组与规则（passthrough）
- iOS：策略组展示订阅全部组；连接中改为太极双鱼动效；谷歌/Telegram 分流修复
EOF
)"

echo "== Publish BashX ${VERSION} → ${RELEASES_PAGE} =="

"$ROOT/scripts/build_dmg.sh"

[[ -f "$DMG" && -f "$STABLE" ]] || { echo "DMG missing"; exit 1; }

cd "$ROOT"
git add README.md 2>/dev/null || true
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "docs: update README for release ${VERSION}" || true
fi

echo "Pushing to origin…"
git push origin HEAD

if gh release view "$TAG" &>/dev/null; then
  echo "Release $TAG exists — uploading assets…"
  gh release upload "$TAG" "$DMG" "$STABLE" --clobber
else
  gh release create "$TAG" "$DMG" "$STABLE" --title "BashX ${VERSION}" --notes "$RELEASE_NOTES"
fi

echo ""
echo "Done."
echo "  Releases: ${RELEASES_PAGE}"
echo "  Latest:   ${RELEASES_PAGE}/latest"
echo "  DMG:      ${RELEASES_PAGE}/latest/download/BashX.dmg"
