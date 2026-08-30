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

# ---------------------------------------------------------------------------
# Patch mihomo: NEVER ForwarderBindInterface when injecting NE FileDescriptor.
#
# Stock v1.19.12 has an inverted getTunnelName check:
#   err != nil → sets ForwarderBindInterface=true (often with empty name)
# That blackholes egress for socketpair AND can bind dials to utun on NE.
# BaoLianDeng "works" on utun only because getTunnelName succeeds and the
# buggy branch is skipped — socketpair path is still broken without this patch.
# ---------------------------------------------------------------------------
patch_mihomo_fd_bind() {
  local gopath mod f
  gopath="$(go env GOPATH)"
  mod="$(ls -d "$gopath"/pkg/mod/github.com/metacubex/mihomo@v1.19.* 2>/dev/null | sort -V | tail -1 || true)"
  [[ -n "${mod:-}" && -d "$mod" ]] || { echo "WARN: mihomo module not found, skip FD bind patch"; return 0; }
  f="$mod/listener/sing_tun/server.go"
  [[ -f "$f" ]] || return 0
  chmod -R u+w "$mod"
  python3 - "$f" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = "BASHX_NE_FD_BIND_PATCH"
if marker in text:
    print(f"already patched: {path}")
    sys.exit(0)
pattern = re.compile(
    r"\tif options\.FileDescriptor > 0 \{\n"
    r"\t\tif tunName, err := getTunnelName\(int32\(options\.FileDescriptor\)\); err != nil \{\n"
    r"\t\t\tstackOptions\.TunOptions\.Name = tunName\n"
    r"\t\t\tstackOptions\.ForwarderBindInterface = true\n"
    r"\t\t\}\n"
    r"\t\}",
    re.M,
)
repl = (
    "\tif options.FileDescriptor > 0 {\n"
    f"\t\t// {marker}: NE injects fd — never ForwarderBindInterface (utun bind = blackhole).\n"
    "\t\tif tunName, err := getTunnelName(int32(options.FileDescriptor)); err == nil {\n"
    "\t\t\tstackOptions.TunOptions.Name = tunName\n"
    "\t\t}\n"
    "\t}"
)
new, n = pattern.subn(repl, text, count=1)
if n != 1:
    # Fallback: just strip ForwarderBindInterface assignment in that block
    new2, n2 = re.subn(
        r"(\tif options\.FileDescriptor > 0 \{[\s\S]*?)(\t\t\tstackOptions\.ForwarderBindInterface = true\n)",
        r"\1",
        text,
        count=1,
    )
    if n2 != 1:
        print(f"WARN: could not patch {path}", file=sys.stderr)
        sys.exit(0)
    new = new2
    n = n2
path.write_text(new)
print(f"patched FD bind ({n}x): {path}")
PY
}

echo "==> Patching mihomo NE FileDescriptor bind"
patch_mihomo_fd_bind

echo "==> gomobile bind (several minutes)..."
mkdir -p "$ROOT/Framework"
rm -rf "$OUT"

# with_gvisor: system-stack TCP needs kernel listener; iOS packetFlow bridge requires userspace TCP.
gomobile bind -target=ios -tags=with_gvisor -ldflags="-s -w -checklinkname=0" -o "$OUT" .

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
