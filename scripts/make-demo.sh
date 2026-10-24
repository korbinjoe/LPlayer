#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/artifacts/demo"
export PALM_DEMO_OUTPUT="$OUTPUT"
mkdir -p "$OUTPUT"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo '找不到 ffmpeg。请先运行：brew install ffmpeg' >&2
  exit 1
fi

# Render labels through macOS so this also works with FFmpeg builds without
# the optional drawtext / FreeType filter. Temporary frames stay task-local.
FRAMES="$(mktemp -d "$OUTPUT/.render-XXXXXX")"
trap 'rm -rf "$FRAMES"' EXIT
/usr/bin/swift - "$FRAMES" <<'SWIFT'
import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}
func writePNG(_ url: URL, width: Int, height: Int, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ shade: NSColor, mono: Bool = false) {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium) : NSFont.systemFont(ofSize: size, weight: .medium)
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: shade])
}
for episode in 1...2 {
    let tag = String(format: "%02d", episode)
    let directory = folder.appendingPathComponent(tag)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let background = episode == 1 ? color(0.06, 0.18, 0.26) : color(0.20, 0.13, 0.27)
    let accent = episode == 1 ? color(0.42, 0.88, 0.72) : color(0.96, 0.74, 0.40)
    for second in 0..<48 {
        try writePNG(directory.appendingPathComponent(String(format: "frame-%02d.png", second)), width: 1280, height: 720) {
            background.setFill()
            NSRect(x: 0, y: 0, width: 1280, height: 720).fill()
            color(1, 1, 1, alpha: 0.05).setStroke()
            let grid = NSBezierPath()
            for x in stride(from: 0, through: 1280, by: 80) { grid.move(to: NSPoint(x: x, y: 0)); grid.line(to: NSPoint(x: x, y: 720)) }
            for y in stride(from: 0, through: 720, by: 80) { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: 1280, y: y)) }
            grid.lineWidth = 1
            grid.stroke()
            color(1, 1, 1, alpha: 0.13).setStroke()
            let border = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 1120, height: 560), xRadius: 18, yRadius: 18)
            border.lineWidth = 2
            border.stroke()
            label("PALM  /  EPISODE \(tag)", 110, 570, 26, color(1, 1, 1, alpha: 0.65))
            label("ONE HAND. JUST WATCH.", 110, 500, 46, .white)
            label(String(format: "00:00:%02d", second), 110, 334, 86, accent, mono: true)
            label("A / D seek     W / S volume     SPACE pause", 110, 116, 23, color(1, 1, 1, alpha: 0.55))
        }
    }
    try writePNG(directory.appendingPathComponent("arrow.png"), width: 140, height: 80) {
        label(">>>", 0, 10, 54, accent)
    }
}
SWIFT

# Synthetic footage; no downloads, personal media, or copyrighted source clips.
for episode in 01 02; do
  ffmpeg -hide_banner -loglevel warning -y \
    -framerate 1 -i "$FRAMES/$episode/frame-%02d.png" \
    -loop 1 -i "$FRAMES/$episode/arrow.png" \
    -f lavfi -i 'sine=frequency=220:sample_rate=48000:duration=48' \
    -filter_complex "[0:v]fps=30[base];[base][1:v]overlay=x='110+mod(t*135,920)':y=445:format=auto,format=yuv420p[video]" \
    -map '[video]' -map 2:a:0 \
    -af 'volume=0.025,afade=t=in:d=1,afade=t=out:st=47:d=1' \
    -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 96k -movflags +faststart -t 48 \
    "$OUTPUT/Palm Demo $episode.mp4"
done

/usr/bin/python3 <<'PY'
import os
from pathlib import Path

folder = Path(os.environ['PALM_DEMO_OUTPUT'])
chinese = [
    '欢迎使用掌映。这是一段完全合成的演示视频。',
    '用左手操作：空格暂停，A 和 D 后退与前进。',
    'W 和 S 调整音量，Q 和 E 调整播放速度。',
    '画面里的计时器与移动箭头可用于检查定位。',
    '尝试切换字幕，或者打开同目录里的下一集。',
    '关闭后再次打开，检查是否记住了观看位置。',
]
english = [
    'Welcome to Palm. This demo is entirely synthetic.',
    'One hand: Space to pause, A and D to seek.',
    'W and S change volume. Q and E change playback speed.',
    'Use the clock and moving arrows to check seeking.',
    'Try switching subtitles or opening the next episode.',
    'Reopen the file to check your saved position.',
]
def timestamp(seconds):
    return f'00:00:{seconds:02d},000'
for episode in ('01', '02'):
    for language, lines in [('zh-Hans', chinese), ('en', english)]:
        blocks = [f'{i + 1}\n{timestamp(i * 8)} --> {timestamp((i + 1) * 8 - 1)}\n{text}\n' for i, text in enumerate(lines)]
        (folder / f'Palm Demo {episode}.{language}.srt').write_text('\n'.join(blocks), encoding='utf-8')
PY

for episode in 01 02; do
  ffmpeg -hide_banner -loglevel warning -y \
    -i "$OUTPUT/Palm Demo $episode.mp4" \
    -i "$OUTPUT/Palm Demo $episode.zh-Hans.srt" \
    -i "$OUTPUT/Palm Demo $episode.en.srt" \
    -map 0:v:0 -map 0:a:0 -map 1:0 -map 2:0 -c:v copy -c:a copy -c:s srt \
    -metadata:s:s:0 language=zho -metadata:s:s:0 title='简体中文' \
    -metadata:s:s:1 language=eng -metadata:s:s:1 title='English' \
    -disposition:s:0 default -disposition:s:1 0 \
    "$OUTPUT/Palm Demo $episode.mkv"
done
echo "演示素材已生成：$OUTPUT"
