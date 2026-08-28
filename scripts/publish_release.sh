#!/usr/bin/env bash
# Build DMG, push git, create GitHub Release with versioned + BashX.dmg assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BashX/Info.plist")"
DMG="$ROOT/dist/BashX-${VERSION}.dmg"
STABLE="$ROOT/dist/BashX.dmg"
TAG="v${VERSION}"
RELEASES_PAGE="https://github.com/linux503/BashX/releases"

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
  NOTES="$ROOT/dist/release-notes-${VERSION}.md"
  if [[ -f "$NOTES" ]]; then
    gh release create "$TAG" "$DMG" "$STABLE" --title "BashX ${VERSION}" --notes-file "$NOTES"
  else
    gh release create "$TAG" "$DMG" "$STABLE" --title "BashX ${VERSION}" --notes "BashX ${VERSION}"
  fi
fi

echo ""
echo "Done."
echo "  Releases: ${RELEASES_PAGE}"
echo "  Latest:   ${RELEASES_PAGE}/latest"
echo "  DMG:      ${RELEASES_PAGE}/latest/download/BashX.dmg"
