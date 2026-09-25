#!/bin/bash
# Claude Code on the web: install the headless Godot binary and build the import cache, so
# `bash tools/ci/validate.sh` works from the first prompt.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
godot="$(bash tools/ci/install_godot.sh)"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export GODOT=\"$godot\"" >> "$CLAUDE_ENV_FILE"
fi
"$godot" --headless --path . --import >/dev/null 2>&1 || true
echo "Godot ready: $godot (run: bash tools/ci/validate.sh)"
