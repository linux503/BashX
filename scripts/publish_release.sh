#!/usr/bin/env bash
# Build DMG, push git, create GitHub Release with versioned + BashX.dmg assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BashX/Info.plist")"
DMG="$ROOT/dist/BashX-${VERSION}.dmg"
STABLE="$ROOT/dist/BashX.dmg"
TAG="v${VERSION}"
RELEASES_PAGE="https://github.com/linux503/BashX/releases"
RELEASE_NOTES="$(cat <<EOF
## BashX ${VERSION}

- Mac 极简首页：当前节点更突出；域名规则默认打开「基础规则」
- Mac 完整面板：策略组/分流菜单整理为一排；监控与布局优化
- Mac 极简：iOS 同款 hero、可切规则模式与节点
- iOS：订阅卡片色差、更紧凑；连接 URL 默认隐藏可点展开
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
