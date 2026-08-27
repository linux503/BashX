#!/usr/bin/env bash
# Build MihomoCore.xcframework for BashX iOS Packet Tunnel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/Go/mihomo-bridge"
OUT="$ROOT/Framework/MihomoCore.xcframework"
STUB_S="$ROOT/PacketTunnel/connPool_stub.s"

export PATH="/opt/homebrew/bin:/usr/local/go/bin:${PATH:-}"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GO111MODULE=on

if ! command -v go >/dev/null; then
  echo "Go not found. Install: brew install go"
  exit 1
fi

export PATH="$(go env GOPATH)/bin:$PATH"

echo "==> Installing gomobile"
go install "golang.org/x/mobile/cmd/gomobile@latest"
go install "golang.org/x/mobile/cmd/gobind@latest"
gomobile init 2>/dev/null || true

cd "$BRIDGE"
echo "==> go mod tidy"
go mod tidy

echo "==> gomobile bind (several minutes)..."
mkdir -p "$ROOT/Framework"
rm -rf "$OUT"

gomobile bind -target=ios -ldflags="-checklinkname=0" -o "$OUT" .

# Go 1.27 + gomobile may leave http2.(*Transport).connPool undefined — inject stub.
patch_slice() {
  local binary="$1"
  local sdk="$2"
  local arch="$3"
  local asm="$4"
  [[ -f "$binary" ]] || return 0
  local tmp
  tmp="$(mktemp -d)"
  xcrun -sdk "$sdk" clang -arch "$arch" -c "$asm" -o "$tmp/stub.o"
  (
    cd "$tmp"
    # Thin if needed
    if lipo -info "$binary" 2>/dev/null | grep -q 'Architectures'; then
      lipo -thin "$arch" "$binary" -output lib.a || cp "$binary" lib.a
    else
      cp "$binary" lib.a
    fi
    ar x lib.a
    ar r lib.a stub.o
    ranlib lib.a
    cp lib.a "$binary"
  )
  rm -rf "$tmp"
  echo "patched $binary ($arch)"
}

echo "==> Patching gomobile archive stub"
if [[ -f "$STUB_S" ]]; then
  patch_slice "$OUT/ios-arm64/MihomoCore.framework/MihomoCore" iphoneos arm64 "$STUB_S"
fi

echo "==> Done: $OUT"
du -sh "$OUT"
echo "Next: cd \"$ROOT\" && xcodegen generate && open BashX.xcodeproj"
echo "Scheme: BashXiOS — set Team, plug in iPhone, Run."
