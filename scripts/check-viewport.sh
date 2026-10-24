#!/bin/bash
set -euo pipefail

viewport_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
viewport_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lplayer-viewport.XXXXXX")"
trap 'rm -rf "$viewport_tmp"' EXIT

swiftc -swift-version 5 -parse-as-library \
  "$viewport_root/Sources/PalmPlayer/VideoViewport.swift" \
  "$viewport_root/scripts/ViewportChecks.swift" \
  -o "$viewport_tmp/viewport-checks"
"$viewport_tmp/viewport-checks"
