# Controller interaction checks

Run from the repository root on macOS with the project's Swift, libmpv,
pkg-config and FFmpeg dependencies installed:

```sh
python3 scripts/interaction/run-controller.py
```

Playback W/S mirrors Up/Down (previous/next video), and A/D mirrors Left/Right
(seek ±5 seconds). Right-hand I/K/J/L mirrors the same arrows. Shift+up/down
pairs adjust volume; Shift+left/right pairs seek ±30 seconds. In the playlist,
these directions select/browse; in Quick Controls, they navigate/adjust.
Those visible modes retain priority even with Shift. Q/E and U/O retain speed
adjustment. Long-held video keys switch only once.

The defaults use configuration schema 2. Existing v1 hands with customized
bindings retain their previous complete effective layout. A hand without
customization adopts the new preset; Reset All adopts the new preset.

The fixture snapshots every production Swift file, then checks the actual
`handleKey` routing, visible-mode priority, original 15 Quick Control actions,
fixed Settings entry, subtitle/speed buttons, and one-hand mappings. It hides
its owned window, uses local NSEvents, three generated silent clips, scratch
media/history/grants, and a removed-on-exit UserDefaults suite. Only the
key-window guard is omitted from the temporary handler copy; the remaining
ownership, editable-input, sheet and repeat guards remain intact. Production
sources are never modified.

Volume checks enable normal history only inside the scratch store and seed
three bookmarks with different legacy per-file volumes. The actual transport
slider sets a global level, then real W/S, playlist row and Enter routes resume
those files without changing it. Rapid volume keys followed immediately by a
file switch verify that the newest target wins over a delayed engine snapshot.
An explicit zero level must survive switching and persistence. Private-mode
checks compare both the history records and exact history-file bytes before and
after playback, while allowing the global volume preference to persist. The
first controller is terminated before a fresh hidden controller and engine
start in the same isolated suite, checking that zero survives restart and a
normal resume with conflicting legacy file history.

Generated hashes, adapter descriptions, log and assertion results are written
to `artifacts/controller-check/`, which is excluded from version control. The
runner verifies production-source hashes again after execution and fails if
they changed during the check.

This fixture does not establish physical keyboard input, foreground window
focus, fullscreen Spaces, system dialogs or physical trackpad behavior.
`scripts/check-core.sh` provides independent command mapping, modifier,
persistence and migration checks.
