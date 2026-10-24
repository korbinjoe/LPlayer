# LPlayer

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

A local video player for macOS, built with AppKit and libmpv. Keep one hand on the keyboard to browse videos, seek, adjust playback, and open controls through a native interface.

## Features

- **One-hand controls.** Left-hand WASD and right-hand IJKL presets mirror the arrow keys in playback, the playlist, and Quick Controls. Shortcuts can be customized for each hand.
- **Local playback.** Open files or folders, drag videos into the window, or open them from Finder. The standard build discovers sibling videos and matching subtitles in the background.
- **Playlist previews.** Click a video to play it, or browse with the keyboard to see a silent thumbnail preview before confirming. Compact and large-preview layouts are available.
- **Global volume.** Volume adjustments apply to every video and survive file switches and app restarts. A video's old history cannot override the current level.
- **Resume and private playback.** Restore per-file progress, speed, subtitles, and audio-track selection. Private playback does not add watch history or persistent file grants.
- **Trackpad and timeline.** Pinch to zoom up to 5×, pan with two fingers, and hover over the timeline for an independent thumbnail preview.
- **Native presentation.** AppKit controls, an automatically hiding transport, a Manrope wordmark, and a nonmodal shortcut reference sidebar.

The application interface currently supports **English** and **Simplified Chinese**. The README translations above are documentation languages; they do not add application UI languages.

## Build and run

Requires macOS 13+, Xcode Command Line Tools, and Homebrew. The standard local build has been validated on Apple Silicon.

From the repository root:

```sh
brew install mpv pkg-config
./scripts/build-app.sh
open dist/LPlayer.app
```

You can also double-click [`打开LPlayer.command`](打开LPlayer.command). The launcher builds the app when needed and opens it; it rebuilds after source changes.

On launch, use **Open Video…**, press `⌘O`, drop a video into the window, or try one of the three bundled demo films. LPlayer can be chosen in Finder's **Open With** menu; it does not change the system's default player automatically.

This is a local development build with ad-hoc signing. A Developer ID-signed, notarized installer has not been published.

## Languages and settings

The app starts in **English**, independently of the macOS language, and remembers your selection. Switch between English and Simplified Chinese in **Settings → General → Language**, or through **LPlayer → Language**.

Language changes update menus, tooltips, Quick Controls, the playlist, shortcut help, and playback error messages. Media filenames and subtitle text stay as authored. Native system dialogs use the language selected when the app starts.

Settings contains **General**, **Shortcuts**, and **About**. Open it from **LPlayer → Settings…**, the transport's **More** menu, or the bottom of Quick Controls. `⌘,` opens the **Shortcuts** page directly. General settings also include the default hand layout and pan sensitivity.

## Keyboard controls

These are the current default presets. Previously customized layouts retain their effective bindings during upgrades; resetting a hand's shortcuts adopts the new defaults.

| Action | Left hand | Right hand |
| --- | --- | --- |
| Play / pause | `Space` | `Space` |
| Previous / next video | `W` / `S` | `I` / `K` |
| Back / forward 5 seconds | `A` / `D` | `J` / `L` |
| Back / forward 30 seconds | `Shift+A` / `Shift+D` | `Shift+J` / `Shift+L` |
| Volume up / down | `Shift+W` / `Shift+S` | `Shift+I` / `Shift+K` |
| Slower / faster | `Q` / `E` | `U` / `O` |
| Normal speed | `R` | `P` |
| Playlist | `T` | `'` (also `B`) |
| Quick Controls | `C` | `,` |
| Shortcut help | `V` | `Y` |
| Full screen | `F` | `H` |
| Toggle subtitles | `G` | `;` |
| Undo seek | `Z` | `M` |
| Fit video to window | `0` | `0` |

`W/A/S/D` and `I/J/K/L` match `↑/←/↓/→`. Their behavior follows the visible mode:

| Mode | Up / down | Left / right | Space / Enter |
| --- | --- | --- | --- |
| Playback | Previous / next video | Seek 5 seconds | Space plays / pauses |
| Playlist | Select and silently preview | Keep the main video unchanged | Play the selected item |
| Quick Controls | Select a control | Adjust its value | Activate or reset the control |

During playback, `Shift+↑/↓` adjusts volume and `Shift+←/→` seeks 30 seconds, matching the corresponding letter keys. In the playlist and Quick Controls, Shift plus a direction still belongs to that visible mode. Holding a video-switch key does not skip multiple videos.

Additional shortcuts:

- `⌘O`: open a video or folder.
- `⌘L`: toggle the playlist.
- `⌘[` / `⌘]`: previous / next video.
- `⌘N`: toggle private playback.
- `0` or `⌘0`: fit the picture to the window.
- `?`, `/`, or `⌘/`: toggle shortcut help.
- `Esc`: close the active panel or sidebar, then exit full screen.

The shortcut reference is nonmodal: playback commands remain available while it is open. File dialogs and editable text fields keep normal text input.

### Playlist and Quick Controls

The playlist starts closed. A mouse click plays a row immediately; keyboard navigation selects it and starts a silent preview after a short pause. `Home` / `End` selects the first / last item. Enter or Space confirms without closing playlist navigation. Confirming the current video resumes at its current position; a finished video can restart.

The playlist and Quick Controls are mutually exclusive. Quick Controls retains 15 actions: speed, volume, zoom, pan sensitivity, subtitle visibility, subtitle timing, audio track, subtitle track, hand layout, private playback, open files or folders, folder access, playlist, language, and shortcut customization. The fixed **Settings…** footer is an additional keyboard target.

The subtitle button toggles subtitles directly. The speed button opens Quick Controls at the speed row; use the horizontal navigation keys to adjust it in 0.1× steps.

### Customize shortcuts

In **Settings → Shortcuts**, search the 29 actions and record bindings independently for each hand. Letters, numbers, function keys, and modifier combinations are supported. Press Esc to cancel recording or Delete to clear an editable primary binding. Conflicts and reserved shortcuts are rejected; fixed navigation and menu aliases remain available. Changes apply immediately and persist locally.

## Volume, history, and privacy

Volume is a player-wide preference shared by all files, including private playback, and survives restarting the app. The legacy volume field in old bookmarks is retained for format compatibility and is no longer restored.

Normal playback keeps the 30 most recent files in `~/Library/Application Support/PalmPlayer/history.json`. It restores progress, speed, subtitle timing and visibility, and selected audio/subtitle tracks. Completed files restart from the beginning. History writes run in the background; the original application identifier and history location remain compatible with the earlier PalmPlayer name.

The standard local build opens a selected file immediately, then discovers sibling videos and matching subtitles without blocking playback. Discovery scans only that directory, skips hidden files and subdirectories, and sorts naturally, such as episodes 1, 2, and 10. Explicitly selecting several files preserves their selection order. Playback advances to the next queue item when a video ends.

Private playback saves normal progress before being enabled, then stops reading or writing playback history for newly opened files. Those files start from the beginning; existing history is retained. The global volume and application preferences still persist. You can clear watch history from the **File** menu.

## Trackpad and previews

Pinch over the video to zoom around the pointer. When zoomed, slide two fingers without pressing the trackpad to move the picture; movement follows the fingers and stops when they lift. Pan sensitivity is adjustable from 25% to 150%, with 100% as the default. The picture stays within its bounds, and switching videos resets zoom and pan.

Double-tap with two fingers to switch between 2× zoom and fit-to-window, or press `0` / `⌘0` to reset. Gestures that start over the playlist, controls, or help sidebar retain that surface's interaction.

Timeline thumbnails use a separate low-resolution decoder and an in-memory cache, leaving the main playback position unchanged. Playlist motion previews are also isolated and have audio disabled. Preview images are not written to disk.

## Interactive HTML prototype

A frontend-only prototype is included at [`prototypes/lplayer`](prototypes/lplayer/README.md). It uses local video, fonts, and icons, with no npm dependencies:

```sh
python3 prototypes/lplayer/serve.py
```

Open <http://127.0.0.1:4178/>. The prototype currently has a Chinese interface. Its keyboard contexts mirror the native player, and capabilities requiring native decoding or macOS APIs are labeled. Local files play through browser object URLs and are not uploaded; browser format support differs from libmpv. The prototype does not implement the native history or file-permission backend.

The three bundled demo films are silent clips made from AI-generated landscape stills with slow FFmpeg camera movement and SRT subtitles, **not location footage**. See [demo provenance](Resources/Demo/README.txt).

## Validation

Additional playback checks require the FFmpeg command-line tools:

```sh
brew install ffmpeg
./scripts/check-core.sh
./scripts/check-viewport.sh
./scripts/make-demo.sh
./scripts/check-engine.sh
./scripts/check-gestures.sh
./scripts/check-thumbnails.sh
./scripts/check-seeking.sh production-final Sources/PalmPlayer
python3 scripts/interaction/run-controller.py
```

Core checks exercise mappings, modifiers, history, persistence, and shortcut migration. The [controller fixture](scripts/interaction/README.md) exercises the actual handler with generated media and isolated storage, including global volume across historical files and restart. Generated reports live under ignored `artifacts/`; historical evidence is not bundled with the source.

Engine and gesture checks may briefly show independent test windows. The hidden controller fixture uses local events and does not establish physical keyboard input, foreground focus, fullscreen Spaces, or system dialog behavior. These checks do not replace testing on real devices and media. See the [performance notes (中文)](docs/PERFORMANCE.md) for prior measurements and scope.

## Sandbox preview and distribution

A separate sandbox preview uses controlled dependencies and an independent app identity/container. Its documented target is Apple Silicon and macOS 15+. It has not been submitted to or approved by the Mac App Store:

```sh
./scripts/build-store-deps.sh
./scripts/build-store-app.sh --preview
./scripts/check-store-app.py
```

The sandbox initially plays only the selected file. Use `⌘⇧O` to grant read-only folder access for sibling videos and matching subtitles; grants use security-scoped bookmarks and can be cleared from the File menu. Private mode does not add persistent grants or watch history.

The standard build bundles the non-system libraries its executable actually uses, rewrites their load paths, validates them, and signs the app ad hoc. Builds replace `dist/LPlayer.app` atomically after keeping a backup and do not restart a running player. The bundled Manrope font does not need a system installation.

Dependency versions and license notices are in [`Resources/licenses`](Resources/licenses/README.md). The standard Homebrew-based build includes GPL-licensed components; the sandbox has a separate dependency configuration. The included notices are not a complete corresponding-source distribution. See [release preparation (中文)](docs/APP_STORE_RELEASE.md) and [historical sandbox validation (中文)](docs/APP_STORE_VALIDATION.md).

The renderer currently uses libmpv's OpenGL pipeline. Metal rendering, online subtitle search, automatic subtitle timing calibration, and AI features are not implemented. HDR correctness, audio passthrough, every codec, and cross-device power use have not been comprehensively validated.
