#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---preview}"
if [ "$#" -gt 1 ] || { [ "$MODE" != '--preview' ] && [ "$MODE" != '--release' ]; }; then
  echo '用法：scripts/build-store-app.sh [--preview|--release]' >&2
  exit 2
fi
PREFIX="${LPLAYER_STORE_DEPS_PREFIX:-$ROOT/.build/store-deps/prefix}"
if [ ! -f "$PREFIX/share/lplayer-deps/manifest.json" ]; then
  echo '缺少受控内核。先运行 scripts/build-store-deps.sh。不会回退到 Homebrew mpv。' >&2
  exit 1
fi
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
ACTUAL_MPV="$(pkg-config --variable=libdir mpv)"
if [ "$ACTUAL_MPV" != "$PREFIX/lib" ]; then
  echo "拒绝链接非受控的 libmpv：$ACTUAL_MPV" >&2
  exit 1
fi
if [ "$MODE" = '--release' ]; then
  if ! xcodebuild -version >/dev/null 2>&1; then
    echo '正式发行需要已选择的完整 Xcode；当前 CLT 只能生成本机沙盒预览。' >&2
    exit 1
  fi
  : "${LPLAYER_APP_SIGN_IDENTITY:?需要 Mac App Distribution 或 Apple Distribution 签名身份}"
  : "${LPLAYER_APP_PROVISION_PROFILE:?需要 Mac App Store provisioning profile 文件路径}"
  if [ "$LPLAYER_APP_SIGN_IDENTITY" = '-' ]; then
    echo '正式发行不能使用 ad-hoc 签名。' >&2
    exit 1
  fi
  if [ ! -f "$LPLAYER_APP_PROVISION_PROFILE" ]; then
    echo '找不到商店 provisioning profile。' >&2
    exit 1
  fi
fi

cd "$ROOT"
python3 "$ROOT/scripts/store/snapshot.py"
swift build -c release --jobs 2 --package-path "$ROOT/.build/store-package" --scratch-path "$ROOT/.build/store-swift" --product LPlayer
BIN_DIR="$(swift build -c release --package-path "$ROOT/.build/store-package" --scratch-path "$ROOT/.build/store-swift" --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/dist/.lplayer-store-XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
export LPLAYER_PACKAGE_ROOT="$ROOT"
export LPLAYER_PACKAGE_PREFIX="$PREFIX"
export LPLAYER_PACKAGE_BINARY="$BIN_DIR/LPlayer"
export LPLAYER_PACKAGE_STAGING="$STAGING"
export LPLAYER_PACKAGE_MODE="$MODE"
/usr/bin/python3 "$ROOT/scripts/store/package.py"
