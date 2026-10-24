#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/LPlayer-icon.png"
TARGET="$ROOT/Resources/LPlayer.icns"
if [ ! -f "$SOURCE" ]; then
  echo "找不到图标原图：$SOURCE。请先提供新的 LPlayer 图标；不会使用旧图替代。" >&2
  exit 1
fi

DIMENSIONS="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$SOURCE")"
WIDTH="$(printf '%s\n' "$DIMENSIONS" | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
HEIGHT="$(printf '%s\n' "$DIMENSIONS" | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
if [ -z "$WIDTH" ] || [ "$WIDTH" != "$HEIGHT" ] || [ "$WIDTH" -lt 1024 ]; then
  echo '图标原图必须是至少 1024×1024 的正方形 PNG。' >&2
  exit 1
fi

ICON_TEMP="$(mktemp -d "$ROOT/Resources/.lplayer-icon.XXXXXX")"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICONSET="$ICON_TEMP/LPlayer.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  /usr/bin/sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_TEMP/LPlayer.icns"
mv "$ICON_TEMP/LPlayer.icns" "$TARGET"
echo "已生成：$TARGET"
