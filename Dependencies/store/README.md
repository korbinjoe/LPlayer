# Controlled playback dependencies

Build the sandbox player's playback engine with:

```sh
scripts/build-store-deps.sh
```

The default output is `.build/store-deps/prefix`. Set `PKG_CONFIG_PATH` to
`$PWD/.build/store-deps/prefix/lib/pkgconfig` before building the Swift app.
The script limits compiler parallelism to two jobs by default; the supported
`LPLAYER_DEPS_JOBS` range is 1–4. It installs Meson and Ninja into a private
Python virtual environment, without changing global Python packages.

The script builds FFmpeg 8.0.1, mpv 0.41.0, libplacebo 7.360.1, HarfBuzz 14.6.0
and libass 0.17.5 from official source archives with fixed SHA256 checks.
An upstream mpv CoreAudio fix, commit `c5d391adba7bd024954d0df1e0405f5749f4d4ca`,
is applied and retained with its checksum. The script contains the full source
URLs, checksums, configuration switches and patch application.

FFmpeg disables GPL, nonfree, version3, external autodetection and networking.
Its own `ffmpeg -L` report identifies the result as LGPL 2.1 or later. mpv
uses `-Dgpl=false`. Rubber Band, x264, x265, VapourSynth, JavaScript, Lua,
Blu-ray and archive support are omitted. VideoToolbox, AudioToolbox, normal
MP4/MKV demuxers and native decoders remain available. libass uses CoreText
font discovery; HarfBuzz disables GLib and Graphite to reduce dependencies.
libplacebo supplies CPU shader helpers with all GPU backends disabled. The
libmpv render API retains mpv's own OpenGL backend and VideoToolbox interop.

The only reused Homebrew components are the exact reviewed versions of
FreeType 2.15.0, FriBidi 1.0.17, libunibreak 8.0, libpng 1.6.59 and Brotli 1.2.0.
No Homebrew mpv or FFmpeg binary is used. The audit follows the entire Mach-O
dependency closure and rejects unreviewed components or version drift. It
downloads each reused component's exact source archive, verifies its SHA256,
and retains its installed build formula and relevant provenance. Rebuilding
those components independently requires following their included formulas.

The generated output at `prefix/share/lplayer-deps/` contains:

- `manifest.json`: exact binary paths, hashes, component and selected license.
- `licenses/`: original license texts and notices, including generated code.
- `build-configs/`: source build script, generated configuration, compiler/tool
  versions and reused component formulas.
- `sources/`: actual original source archives, mpv patch and selected CC0 text.

The source distribution is also saved as
`.build/store-deps/lplayer-store-deps-corresponding-source.tar.xz`, with a
separate SHA256 file. `--audit-only` regenerates this metadata and archive
without rebuilding the libraries. The app packaging step can copy these
materials and independently verify every input binary against the manifest.

FreeType is used under the FTL option; fast_float uses its MIT option. The
GLAD-generated loader and Khronos Apache definitions from libplacebo's optional
OpenGL backend are not incorporated. Original dual license texts remain in
the fast_float source archive; this build selects MIT. Dynamic linking and
source inclusion still need an effective recipient library replacement or
relinking mechanism and compatible application distribution terms before a
public release.

## Verification on 2026-10-23

The first built closure contains 16 non-system dynamic libraries. Its actual
maximum Mach-O minimum OS version is macOS 15.0, including the reused font
libraries; the sandbox bundle must declare at least that version. The source
build asks for a 13.0 deployment target, which does not lower existing external
binary requirements. Older OS support requires rebuilding the font closure
and verifying the final minimum version again.

`verify-playback.c` is a small libmpv integration check. Compile and run it with:

```sh
clang Dependencies/store/verify-playback.c \
  -I .build/store-deps/prefix/include -L .build/store-deps/prefix/lib -lmpv \
  -o .build/store-deps/verify-playback
.build/store-deps/verify-playback "$(pwd)/artifacts/demo/Palm Demo 01.mp4" \
  "$(pwd)/artifacts/demo/Palm Demo 01.zh-Hans.srt"
.build/store-deps/verify-playback "$(pwd)/artifacts/demo/Palm Demo 02.mkv" \
  "$(pwd)/artifacts/demo/Palm Demo 02.en.srt"
```

Both H.264 files played to 0.733 seconds with
`hwdec-current=videotoolbox-copy`; the external Chinese and English subtitle
tracks were selected as `sid=1` and `sid=3`. This verifies demux, hardware
decoding and subtitle loading through the actual new libmpv. Real-window
rendering, subtitle appearance and App Sandbox permissions require the
separate sandbox app validation; this headless check does not establish them.

`verify-render.c` also exercises the actual libmpv OpenGL render API with a
CGL context and a 640×360 framebuffer. It rendered video, Chinese subtitles
and direct `hwdec=videotoolbox` frames successfully. A separate build under
`prefix-no-glad` disabled libplacebo's OpenGL backend before rebuilding mpv.
For the same static H.264 input, subtitle and paused position of 0.8 seconds,
the original and minimal versions produced byte-identical RGB output with
SHA256 `b4d28c5525e23949bdf99e0abd9c2a2e4ab63095c34e1ccdbeff3dbb001d25b3`.
The canonical dependency build now uses this tested minimal configuration.
