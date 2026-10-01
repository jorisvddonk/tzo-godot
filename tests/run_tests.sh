#!/usr/bin/env sh
# Runs the tzo-godot test suite headless.
#
# Usage:
#   tests/run_tests.sh [path-to-godot]
#
# If the native extension has been built (see README), native parity tests run
# as well; otherwise they are skipped and only the GDScript backend is tested.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" != "" ]; then
	GODOT="$1"
elif command -v godot >/dev/null 2>&1; then
	GODOT="godot"
elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
	echo "error: could not find a Godot binary; pass one as the first argument" >&2
	exit 1
fi

mkdir -p "$ROOT/.godot"

# Register the GDExtension so the native backend is exercised when available.
# This is the file the editor would normally generate during import.
if [ -d "$ROOT/build/tzo-godot/lib" ]; then
	printf 'res://tzo-godot.gdextension\n' > "$ROOT/.godot/extension_list.cfg"
else
	echo "note: native extension not built; running GDScript backend tests only" >&2
	: > "$ROOT/.godot/extension_list.cfg"
fi

exec "$GODOT" --headless --path "$ROOT" --script res://tests/run_tests.gd
