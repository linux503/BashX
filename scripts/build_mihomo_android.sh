#!/usr/bin/env bash
# Build MihomoCore.aar for BashX Android (Galaxy Z Fold 6 / arm64).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/Go/mihomo-bridge"
OUT_DIR="$ROOT/Android/libs"
OUT="$OUT_DIR/MihomoCore.aar"

export PATH="/opt/homebrew/bin:/usr/local/go/bin:${ANDROID_HOME:-${HOME}/Library/Android/sdk}/ndk-bundle:${PATH:-}"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GO111MODULE=on

if ! command -v go >/dev/null; then
  echo "Go not found. Install: brew install go"
  exit 1
fi

if [[ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  for candidate in "$HOME/Library/Android/sdk" /opt/homebrew/share/android-commandlinetools; do
    if [[ -d "$candidate" ]]; then
      export ANDROID_HOME="$candidate"
      break
    fi
  done
fi
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ANDROID_HOME" || ! -d "$ANDROID_HOME" ]]; then
  echo "ANDROID_HOME not set. Install Android SDK / Android Studio."
  exit 1
fi

NDK_DIR="${ANDROID_NDK_HOME:-}"
if [[ -z "$NDK_DIR" || ! -d "$NDK_DIR" ]]; then
  NDK_DIR="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
if [[ -z "${NDK_DIR:-}" && -d /opt/homebrew/share/android-ndk ]]; then
  NDK_DIR="/opt/homebrew/share/android-ndk"
fi
if [[ -z "${NDK_DIR:-}" || ! -d "$NDK_DIR" ]]; then
  echo "Android NDK not found. Install NDK via Android Studio SDK Manager, or: brew install --cask android-ndk"
  exit 1
fi
export ANDROID_NDK_HOME="$NDK_DIR"
echo "==> NDK: $ANDROID_NDK_HOME"

export PATH="$(go env GOPATH)/bin:$PATH"
echo "==> Installing gomobile"
go install "golang.org/x/mobile/cmd/gomobile@latest"
go install "golang.org/x/mobile/cmd/gobind@latest"
gomobile init 2>/dev/null || true

cd "$BRIDGE"
echo "==> go mod tidy"
go mod tidy

mkdir -p "$OUT_DIR"
echo "==> gomobile bind android/arm64"
# Fold 6 is arm64-v8a. API 26 matches minSdk. with_gvisor matches iOS TUN stack.
gomobile bind \
  -target=android/arm64 \
  -androidapi 26 \
  -tags=with_gvisor \
  -ldflags="-checklinkname=0" \
  -javapkg=bridge \
  -o "$OUT" \
  .

echo "==> wrote $OUT ($(du -h "$OUT" | awk '{print $1}'))"
