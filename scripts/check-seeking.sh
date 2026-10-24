#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:-production}"
SOURCE="${2:-$ROOT/Sources/PalmPlayer}"
OUTPUT="$ROOT/artifacts/seek-benchmark"
MEDIA="$OUTPUT/long-gop-1080p.mp4"
mkdir -p "$OUTPUT"
if [ ! -f "$MEDIA" ]; then
  ffmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1920x1080:rate=30' -t 60 -an -c:v libx264 -preset ultrafast -crf 25 -pix_fmt yuv420p -x264-params 'keyint=300:min-keyint=300:scenecut=0:bframes=3' -movflags +faststart "$MEDIA"
fi
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/lplayer-seek.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
python3 - "$SOURCE/MPVEngine.swift" "$TEMP/MPVEngine.swift" <<'PY'
import sys
source=open(sys.argv[1]).read()
hooks='''
    var benchmarkOnEvent: ((String, Double, Double) -> Void)?
    var benchmarkOnFrame: ((Double) -> Void)? {
        didSet { (videoView as? MPVVideoView)?.benchmarkOnFrame = benchmarkOnFrame }
    }
    func benchmarkReadProperties(_ completion: @escaping ([String: String]) -> Void) {
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else { return }
            var values: [String: String] = [:]
            for name in ["mpv-version", "ffmpeg-version", "hwdec-current", "video-codec", "video-format", "video-params/w", "video-params/h", "container-fps", "current-vo"] {
                if let value = mpv_get_property_string(core, name) { values[name] = String(cString: value); mpv_free(value) }
            }
            DispatchQueue.main.async { completion(values) }
        }
    }
    private func benchmarkEmit(_ name: String, core: OpaquePointer) {
        let time = ProcessInfo.processInfo.systemUptime
        var position = -1.0
        _ = mpv_get_property(core, "time-pos", MPV_FORMAT_DOUBLE, &position)
        DispatchQueue.main.async { [weak self] in self?.benchmarkOnEvent?(name, time, position) }
    }
'''
assert source.count('final class MPVEngine {')==1
source=source.replace('final class MPVEngine {','final class MPVEngine {'+hooks,1)
needle='switch event.event_id {'
assert source.count(needle)==1
source=source.replace(needle,'''if event.event_id == MPV_EVENT_SEEK { benchmarkEmit("seeking", core: core) }
            if event.event_id == MPV_EVENT_PLAYBACK_RESTART { benchmarkEmit("playback-restart", core: core) }
            '''+needle,1)
source=source.replace('private final class MPVVideoView: NSOpenGLView {','private final class MPVVideoView: NSOpenGLView {\n    var benchmarkOnFrame: ((Double) -> Void)?',1)
assert source.count('_ = mpv_render_context_update(renderer)')==1
source=source.replace('_ = mpv_render_context_update(renderer)','''let benchmarkUpdate = mpv_render_context_update(renderer)
            var benchmarkFrameInfo = mpv_render_frame_info()
            _ = withUnsafeMutablePointer(to: &benchmarkFrameInfo) {
                mpv_render_context_get_info(renderer, mpv_render_param(type: MPV_RENDER_PARAM_NEXT_FRAME_INFO, data: UnsafeMutableRawPointer($0)))
            }''',1)
assert source.count('mpv_render_context_report_swap(renderer)')==1
source=source.replace('mpv_render_context_report_swap(renderer)','''mpv_render_context_report_swap(renderer)
            let newFrame = benchmarkFrameInfo.flags & UInt64(MPV_RENDER_FRAME_INFO_PRESENT.rawValue) != 0 && benchmarkFrameInfo.flags & UInt64(MPV_RENDER_FRAME_INFO_REDRAW.rawValue | MPV_RENDER_FRAME_INFO_REPEAT.rawValue) == 0
            if benchmarkUpdate & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 && newFrame { benchmarkOnFrame?(ProcessInfo.processInfo.systemUptime) }''',1)
open(sys.argv[2],'w').write(source)
PY
MPV_INCLUDE="$(pkg-config --variable=includedir mpv)"
MPV_LIB="$(pkg-config --variable=libdir mpv)"
FLAGS=(-D LPLAYER_BASELINE_SEEK)
if [[ "$LABEL" == production* ]]; then FLAGS=(-D LPLAYER_PRODUCTION_SEEK); fi
swiftc -swift-version 5 -suppress-warnings \
  "${FLAGS[@]}" \
  -I "$ROOT/Sources/CMpv" -Xcc "-I$MPV_INCLUDE" -L "$MPV_LIB" -lmpv \
  -framework AppKit -framework OpenGL \
  "$ROOT/Sources/PalmPlayer/L10n.swift" \
  "$SOURCE/VideoViewport.swift" "$TEMP/MPVEngine.swift" "$ROOT/scripts/SeekSmoke.swift" \
  -o "$TEMP/SeekSmoke"
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,has_b_frames,duration -show_entries format=duration,size -of json "$MEDIA" > "$OUTPUT/fixture.json"
"$TEMP/SeekSmoke" "$MEDIA" "$OUTPUT/$LABEL.json" "$LABEL" "$TEMP" | tee "$OUTPUT/$LABEL.log"
python3 - "$OUTPUT/$LABEL.json" <<'PY'
import json, statistics, sys
report = json.load(open(sys.argv[1]))
for kind in ('paused-single', 'paused-burst', 'playing-burst'):
    rows = [r for r in report['measurements'] if r['kind'] == kind]
    latency = [r['restartMs'] for r in rows if 'restartMs' in r]
    if latency:
        print(f"MEASURE {kind}: {len(latency)}/{len(rows)} individually completed; input→restart median={statistics.median(latency):.1f} ms; last-request={rows[-1].get('restartMs', -1):.1f} ms")
PY
