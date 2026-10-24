#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA="$ROOT/artifacts/demo/Palm Demo 01.mp4"
if [ "$#" -ne 0 ]; then
  echo "用法：$0（仅使用项目合成素材，不接受个人视频）" >&2
  exit 2
fi
if [ ! -f "$MEDIA" ]; then
  echo '缺少合成演示素材。请先运行 scripts/make-demo.sh。' >&2
  exit 2
fi
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists mpv; then
  echo '找不到 libmpv。请先运行：brew install mpv pkg-config' >&2
  exit 2
fi

TEMP="$(mktemp -d "${TMPDIR:-/tmp}/lplayer-gesture-check.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
MPV_INCLUDE="$(pkg-config --variable=includedir mpv)"
MPV_LIB="$(pkg-config --variable=libdir mpv)"

echo '正在构建独立 AppKit + libmpv 手势检查…'
swiftc -swift-version 5 -suppress-warnings \
  "$ROOT/Sources/PalmPlayer/L10n.swift" \
  -I "$ROOT/Sources/CMpv" -Xcc "-I$MPV_INCLUDE" \
  -L "$MPV_LIB" -lmpv -framework AppKit -framework OpenGL \
  "$ROOT/Sources/PalmPlayer/Commands.swift" \
  "$ROOT/Sources/PalmPlayer/ShortcutBindings.swift" \
  "$ROOT/Sources/PalmPlayer/UIComponents.swift" \
  "$ROOT/Sources/PalmPlayer/PlayerChrome.swift" \
  "$ROOT/Sources/PalmPlayer/VideoViewport.swift" \
  "$ROOT/Sources/PalmPlayer/MPVEngine.swift" "$ROOT/scripts/GestureSmoke.swift" \
  -o "$TEMP/GestureSmoke"
echo '检查合成手势事件与真实视频裁切（后台独立窗口，不操作当前播放器）…'
"$TEMP/GestureSmoke" "$MEDIA"
