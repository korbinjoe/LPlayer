#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/LPlayer.app"
EXECUTABLE="$APP/Contents/MacOS/LPlayer"
rebuild=false
if [ ! -x "$EXECUTABLE" ]; then
  rebuild=true
elif [ "$ROOT/Package.swift" -nt "$EXECUTABLE" ] || [ "$ROOT/scripts/build-app.sh" -nt "$EXECUTABLE" ]; then
  rebuild=true
elif [ -n "$(/usr/bin/find "$ROOT/Sources" -type f -newer "$EXECUTABLE" -print -quit)" ]; then
  rebuild=true
elif [ -n "$(/usr/bin/find "$ROOT/Resources" -type f -newer "$EXECUTABLE" -print -quit)" ]; then
  rebuild=true
fi
if [ "$rebuild" = true ]; then
  "$ROOT/scripts/build-app.sh"
fi
/usr/bin/open -a "$APP" "$@"
