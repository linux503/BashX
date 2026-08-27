#!/usr/bin/env bash
# Download pinned mihomo binaries (gzip) into Resources/Core for app bundling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT/Resources/Core"
VERSION="v1.19.30"

mkdir -p "$CORE_DIR"

fetch_arch() {
  local arch="$1"   # arm64 | amd64
  local out_gz="$CORE_DIR/mihomo-${arch}.gz"
  local file="mihomo-darwin-${arch}-${VERSION}.gz"
  local official="https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${file}"
  local mirror="https://ghfast.top/https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${file}"

  if [[ -f "$out_gz" ]]; then
    local size
    size="$(gunzip -c "$out_gz" 2>/dev/null | wc -c | tr -d ' ')"
    if [[ "$size" -gt 1000000 ]] && gunzip -c "$out_gz" 2>/dev/null | head -c 1 >/dev/null; then
      echo "  ✓ mihomo-${arch}.gz already present ($(du -h "$out_gz" | awk '{print $1}'))"
      return 0
    fi
  fi

  # Offline / flaky network: keep a usable existing file instead of failing the build.
  if [[ -f "$out_gz" ]]; then
    local size
    size="$(gunzip -c "$out_gz" 2>/dev/null | wc -c | tr -d ' ' || echo 0)"
    if [[ "$size" -gt 1000000 ]]; then
      echo "  ⚠ fetch skipped (network); using cached mihomo-${arch}.gz ($(du -h "$out_gz" | awk '{print $1}'))"
      return 0
    fi
  fi

  echo "  → fetching mihomo-${arch} (${VERSION})…"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL --connect-timeout 15 --max-time 180 -o "$tmp" "$official" \
    && ! curl -fsSL --connect-timeout 15 --max-time 180 -o "$tmp" "$mirror"; then
    rm -f "$tmp"
    if [[ -f "$out_gz" ]]; then
      echo "  ⚠ download failed; keeping cached mihomo-${arch}.gz"
      return 0
    fi
    echo "  ✗ failed to download mihomo-${arch} and no cache available" >&2
    return 1
  fi
  # Re-compress at max level for smallest app bundle (upstream gz is often -6).
  gunzip -c "$tmp" | gzip -9 > "${out_gz}.new"
  rm -f "$tmp"
  mv -f "${out_gz}.new" "$out_gz"
  # Drop legacy uncompressed copies to keep bundle lean.
  rm -f "$CORE_DIR/mihomo-${arch}"
  echo "  ✓ mihomo-${arch}.gz ($(du -h "$out_gz" | awk '{print $1}'))"
}

echo "== Fetch mihomo cores (gzip) =="
fetch_arch arm64
fetch_arch amd64
