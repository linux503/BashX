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
## BashX 1.0.4

- 修复在线更新失败：检查/下载会走系统代理、本地 mixed 端口与镜像重试（不再强制直连 GitHub）
- 继承 1.0.3：国内直连分流、Mac 防自动退出、发现新版自动下载安装
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
