#!/usr/bin/env bash
# Export / validate BashX rules for website & CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$ROOT/Resources/rules/bashx-smart-rules.txt"
MANIFEST="$ROOT/Resources/rules/manifest.json"
OUT="$ROOT/dist/rules"

echo "== BashX rules export =="

[[ -f "$RULES" ]] || { echo "missing $RULES"; exit 1; }

VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])")
COUNT=$(grep -cve '^\s*$' -e '^\s*#' "$RULES" || true)

echo "  version: v${VERSION}"
echo "  rules:   ${COUNT} 条"

mkdir -p "$OUT"
cp "$RULES" "$OUT/bashx-smart-rules-v${VERSION}.txt"
cp "$MANIFEST" "$OUT/manifest.json"
cp "$RULES" "$OUT/bashx-smart-rules.txt"

# Clash YAML snippet (rules only)
{
  echo "# BashX Smart Rules v${VERSION}"
  echo "rules:"
  grep -v '^\s*#' "$RULES" | grep -v '^\s*$' | sed 's/^/  - /'
} > "$OUT/bashx-smart-rules.yaml"

echo "  ✓ dist/rules/bashx-smart-rules-v${VERSION}.txt"
echo "  ✓ dist/rules/bashx-smart-rules.yaml"
echo "Done."
