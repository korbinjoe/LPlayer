#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA="${1:-$ROOT/artifacts/demo/Palm Demo 01.mkv}"
EXPECT_FIXTURE=0
if [ "$#" -eq 0 ]; then EXPECT_FIXTURE=1; fi

if [ "$#" -gt 1 ]; then
  echo "用法：$0 [本地视频路径]" >&2
  exit 2
fi
if [ ! -f "$MEDIA" ]; then
  echo "找不到测试视频：$MEDIA" >&2
  echo '默认演示素材可运行 scripts/make-demo.sh 生成。' >&2
  exit 2
fi
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists mpv; then
  echo '找不到 libmpv。请先运行：brew install mpv pkg-config' >&2
  exit 2
fi

# The window exists only for the rendering pipeline. This does not simulate UI
# shortcuts, test the main application's controls, or touch playback history.
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/palm-engine-check.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
MPV_INCLUDE="$(pkg-config --variable=includedir mpv)"
MPV_LIB="$(pkg-config --variable=libdir mpv)"

echo '正在构建独立 libmpv 管线检查…'
swiftc -swift-version 5 -suppress-warnings \
  "$ROOT/Sources/PalmPlayer/L10n.swift" \
  -I "$ROOT/Sources/CMpv" -Xcc "-I$MPV_INCLUDE" \
  -L "$MPV_LIB" -lmpv -framework AppKit -framework OpenGL \
  "$ROOT/Sources/PalmPlayer/VideoViewport.swift" \
  "$ROOT/Sources/PalmPlayer/MPVEngine.swift" "$ROOT/scripts/EngineSmoke.swift" \
  -o "$TEMP/EngineSmoke"
echo '开始实播检查（约 8 秒，会短暂显示独立视频窗口）…'
"$TEMP/EngineSmoke" "$MEDIA" "$TEMP" "$EXPECT_FIXTURE"
