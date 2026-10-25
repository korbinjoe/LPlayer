# Controller interaction checks

Run from the repository root on macOS with the project's Swift, libmpv,
pkg-config and FFmpeg dependencies installed:

```sh
python3 scripts/interaction/run-controller.py
```

Playback W/S mirrors Up/Down (previous/next video), and A/D mirrors Left/Right
(seek ±5 seconds). Right-hand I/K/J/L mirrors the same arrows. Shift+up/down
pairs adjust volume; Shift+left/right pairs seek ±30 seconds. In the playlist,
vertical directions select/browse, including Shift combinations; horizontal
keys seek the current playing video even with a different row selected, using
±5 seconds normally or ±30 seconds with Shift, and repeat while held.
Quick Controls retains all directions for navigation/adjustment, even with Shift. Q/E and U/O retain speed
adjustment. Both hands retain = / + to zoom in, - to zoom out, and 0 / Cmd+0
to fit the picture. The nearby left-hand cluster is 1 / 2 / 3 (fit / out / in);
the right-hand cluster is 7 / 8 / 9. Zoom changes by 25 percentage points,
within 100%–500%; holding zoom-in or zoom-out repeats the adjustment.
Convenience numeric keys and + follow their corresponding editable defaults:
remapping or clearing the action removes its convenience keys, and an existing
custom binding keeps ownership of its key. Compact playback hints prefer an
active nearby numeric key and otherwise display the effective primary.
Long-held video keys switch only once.

The defaults use configuration schema 3. Existing v1 hands with customized
bindings retain their previous complete effective layout. v1/v2 migration adds
the zoom defaults only when the action was not explicitly customized or disabled
and its key is free; a colliding inherited zoom default stays disabled while the
custom binding is preserved. A hand without customization adopts the new preset;
Reset All adopts the new preset. Numeric zoom aliases also honor saved custom
keys in v1, v2 and v3 profiles without changing the current storage schema.

The fixture snapshots every production Swift file, then checks the actual
`handleKey` routing, visible-mode priority, original 15 Quick Control actions,
fixed Settings entry, subtitle/speed buttons, and one-hand mappings. It hides
its owned window, uses local NSEvents, three generated silent clips, scratch
media/history/grants, and a removed-on-exit UserDefaults suite. Only the
key-window guard is omitted from the temporary handler copy; the remaining
ownership, editable-input, sheet and repeat guards remain intact. Production
sources are never modified.

Zoom checks send the numeric cluster through the real handler in playback,
shortcut help, the playlist and Quick Controls, then inspect the actual MPV
viewport and unchanged file, selection, mode, volume and speed. They also check
repeat bounds, the retained original keys, exact modifiers, opposite-hand keys,
editable text input and events belonging to another never-ordered window.

Playlist hover checks exercise the real row configuration, tracking refresh,
layout, clip scrolling and window-focus observers. A hidden owned window supplies
deterministic local pointer coordinates and key state without moving the user's
mouse. Reused rows must clear stale play cues; only the row under the pointer
and a selected nonplaying row may retain the large play icon. Both row bounds
and the clipped visible area constrain hover, including compact and gallery rows.

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
