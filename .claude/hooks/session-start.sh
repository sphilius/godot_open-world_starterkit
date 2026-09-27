#!/bin/bash
# Claude Code on the web: install the headless Godot binary and build the import cache, so
# `bash tools/ci/validate.sh` works from the first prompt. With GAMEDEV_FULL=1 in the cloud
# environment's variables it runs the full tools/setup/gamedev_env.sh instead (Blender, Xvfb and
# Mesa, ffmpeg): about a minute longer per session.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
if [ "${GAMEDEV_FULL:-}" = "1" ]; then
	bash tools/setup/gamedev_env.sh
	echo "Game-dev environment ready (Godot, Blender, Xvfb). Run: bash tools/ci/validate.sh"
	exit 0
fi
godot="$(bash tools/ci/install_godot.sh)"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export GODOT=\"$godot\"" >> "$CLAUDE_ENV_FILE"
fi
"$godot" --headless --path . --import >/dev/null 2>&1 || true
echo "Godot ready: $godot (run: bash tools/ci/validate.sh)"
