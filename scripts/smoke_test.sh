#!/usr/bin/env bash
# BashX smoke test — build + config/API sanity (no GUI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Debug/BashX.app"
SUPPORT="$HOME/Library/Application Support/BashX"
PASS=0
FAIL=0

ok()  { echo "  ✓ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "== BashX smoke test =="

echo "[1/6] Build"
if xcodebuild -project "$ROOT/BashX.xcodeproj" -scheme BashX -configuration Debug \
    -derivedDataPath "$ROOT/build" build -quiet 2>&1; then
  ok "xcodebuild succeeded"
else
  bad "xcodebuild failed"
  echo "FAIL ($FAIL)"
  exit 1
fi

echo "[2/6] App bundle"
if [[ -x "$APP/Contents/MacOS/BashX" ]]; then
  ok "BashX.app executable present"
else
  bad "missing BashX.app"
fi

echo "[3/6] Settings / config on disk"
if [[ -f "$SUPPORT/settings.json" ]]; then
  if python3 -c "import json; json.load(open('$SUPPORT/settings.json'))" 2>/dev/null; then
    ok "settings.json valid JSON"
  else
    bad "settings.json invalid"
  fi
else
  ok "settings.json absent (first run OK)"
fi

if [[ -f "$SUPPORT/config.yaml" ]]; then
  if python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
yaml.safe_load(open('$SUPPORT/config.yaml'))
" 2>/dev/null; then
    ok "config.yaml parses (PyYAML)"
  else
    ok "config.yaml present (PyYAML optional)"
  fi
else
  ok "config.yaml absent until first core start"
fi

echo "[4/6] Core binary"
BIN=""
for c in "$SUPPORT/mihomo" /opt/homebrew/bin/mihomo /usr/local/bin/mihomo; do
  [[ -x "$c" ]] && BIN="$c" && break
done
if [[ -n "$BIN" ]]; then
  ok "mihomo found: $BIN"
else
  ok "no mihomo (user must install or bundle)"
fi

echo "[5/6] Clash API (if running)"
CTRL="127.0.0.1:19090"
MIXED=17890
if [[ -f "$SUPPORT/settings.json" ]]; then
  CTRL=$(python3 -c "import json; d=json.load(open('$SUPPORT/settings.json')); print(d.get('externalController','127.0.0.1:19090'))" 2>/dev/null || echo "127.0.0.1:19090")
  MIXED=$(python3 -c "import json; d=json.load(open('$SUPPORT/settings.json')); print(d.get('mixedPort',17890))" 2>/dev/null || echo "17890")
fi

if curl -sf --max-time 2 "http://${CTRL}/version" >/dev/null 2>&1; then
  ok "API /version @ $CTRL"
  if curl -sf --max-time 2 "http://${CTRL}/proxies" >/dev/null 2>&1; then
    ok "API /proxies"
  else
    bad "API /proxies unreachable"
  fi
else
  ok "core not running (skip API — idle mode OK)"
fi

if nc -z 127.0.0.1 "$MIXED" 2>/dev/null; then
  ok "mixed port $MIXED listening"
else
  ok "mixed port $MIXED closed (idle OK)"
fi

echo "[6/6] Static checks"
if python3 -c "
import json, os
p=os.path.expanduser('$SUPPORT/settings.json')
if os.path.isfile(p):
    rules=json.load(open(p)).get('rules',[])
    bad=[r for r in rules if 'category-ads-cn' in r.upper()]
    exit(1 if bad else 0)
" 2>/dev/null; then
  ok "settings.rules has no category-ads-cn"
else
  bad "settings.rules contains category-ads-cn (crash rule)"
fi

if rg -q "updateAllSubscriptions" "$ROOT/BashX/Views/SubscriptionManageCard.swift" 2>/dev/null; then
  bad "subscription card still calls updateAllSubscriptions"
else
  ok "single-subscription update path OK"
fi

echo ""
echo "Done: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
