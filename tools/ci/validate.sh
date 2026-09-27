#!/usr/bin/env bash
# Headless validation: refresh the import and class cache, then run every test.
# `--import` alone exits 0 even when scripts don't parse; tests/test_project.gd is the parse gate.
#   bash tools/ci/validate.sh [--filter=<text>]
set -euo pipefail

cd "$(dirname "$0")/../.."
godot="${GODOT:-$(bash tools/ci/install_godot.sh)}"

"$godot" --headless --path . --import >/dev/null 2>&1 || true
"$godot" --headless --path . --script res://tests/run_tests.gd -- "$@"
