#!/bin/bash
set -euo pipefail

core_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_tmp="$(mktemp -d "${TMPDIR:-/tmp}/palmplayer-core.XXXXXX")"
trap 'rm -rf "$core_tmp"' EXIT

swiftc -swift-version 5 -parse-as-library \
  "$core_root/Sources/PalmPlayer/L10n.swift" \
  "$core_root/Sources/PalmPlayer/LibraryStore.swift" \
  "$core_root/Sources/PalmPlayer/Commands.swift" \
  "$core_root/Sources/PalmPlayer/ShortcutBindings.swift" \
  "$core_root/Sources/PalmPlayer/SeekScheduler.swift" \
  "$core_root/scripts/CoreChecks.swift" \
  -o "$core_tmp/core-checks"
"$core_tmp/core-checks"
