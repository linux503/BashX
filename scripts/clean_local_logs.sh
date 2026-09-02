#!/usr/bin/env bash
# Truncate BashX runtime / build logs before DMG pack (keeps the bundle lean).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="${BASHX_SUPPORT_DIR:-$HOME/Library/Application Support/BashX}"

human_size() {
  local n="${1:-0}"
  if (( n >= 1048576 )); then
    awk "BEGIN { printf \"%.1fM\", $n / 1048576 }"
  elif (( n >= 1024 )); then
    awk "BEGIN { printf \"%.0fK\", $n / 1024 }"
  else
    printf "%sB" "$n"
  fi
}

truncate_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local sz
  sz="$(stat -f%z "$f" 2>/dev/null || echo 0)"
  : >"$f"
  echo "  ✓ $(basename "$f") ($(human_size "$sz"))"
}

echo "== Clean local logs before pack =="

echo "Runtime ($SUPPORT):"
for name in core.log launch.log tunnel.log; do
  truncate_file "$SUPPORT/$name"
done

echo "Helper (if present):"
for f in \
  "/Library/Application Support/com.bashx.tunhelper/helper.log" \
  "/Library/Application Support/com.bashx.tunhelper/stdout.log" \
  "/Library/Application Support/com.bashx.tunhelper/stderr.log"
do
  truncate_file "$f" 2>/dev/null || true
done

echo "Build tree:"
rm -rf "$ROOT/build-release/Logs" 2>/dev/null || true
while IFS= read -r -d '' f; do
  sz="$(stat -f%z "$f" 2>/dev/null || echo 0)"
  rm -f "$f"
  echo "  ✓ removed ${f#$ROOT/} ($(human_size "$sz"))"
done < <(find "$ROOT/build-release" "$ROOT/dist" -maxdepth 6 -type f -name "*.log" -size +32k -print0 2>/dev/null || true)

truncate_file "/tmp/bashx-launch.log"

echo "Done."
