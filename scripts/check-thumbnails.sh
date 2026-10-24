#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 0 ]; then
  echo '用法：scripts/check-thumbnails.sh（仅使用项目合成素材）' >&2
  exit 2
fi
for media in 'Palm Demo 01.mp4' 'Palm Demo 01.mkv' 'Palm Demo 02.mp4'; do
  if [ ! -f "$ROOT/artifacts/demo/$media" ]; then
    echo '缺少合成演示素材。请先运行 scripts/make-demo.sh。' >&2
    exit 2
  fi
done
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists mpv; then
  echo '找不到 libmpv。请先安装 mpv 和 pkg-config。' >&2
  exit 2
fi
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/lplayer-thumbnails.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
MPV_INCLUDE="$(pkg-config --variable=includedir mpv)"
MPV_LIB="$(pkg-config --variable=libdir mpv)"
mkdir -p "$ROOT/artifacts/thumbnail-preview"

echo '正在构建独立缩略图检查…'
swiftc -swift-version 5 -suppress-warnings \
  "$ROOT/Sources/PalmPlayer/L10n.swift" \
  -I "$ROOT/Sources/CMpv" -Xcc "-I$MPV_INCLUDE" \
  -L "$MPV_LIB" -lmpv -framework AppKit -framework OpenGL \
  "$ROOT/Sources/PalmPlayer/Commands.swift" \
  "$ROOT/Sources/PalmPlayer/ShortcutBindings.swift" \
  "$ROOT/Sources/PalmPlayer/UIComponents.swift" \
  "$ROOT/Sources/PalmPlayer/PlayerChrome.swift" \
  "$ROOT/Sources/PalmPlayer/VideoViewport.swift" \
  "$ROOT/Sources/PalmPlayer/MPVEngine.swift" \
  "$ROOT/Sources/PalmPlayer/ThumbnailGenerator.swift" \
  "$ROOT/scripts/ThumbnailSmoke.swift" -o "$TEMP/ThumbnailSmoke"
echo '检查悬停定位、实际 MP4/MKV 缩略图、取消和独立播放（仅合成素材，不操作当前播放器）…'
"$TEMP/ThumbnailSmoke" "$ROOT/artifacts/demo" "$ROOT/artifacts/thumbnail-preview"
