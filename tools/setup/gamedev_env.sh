#!/usr/bin/env bash
# One-shot setup for a cloud game-dev container (Claude Code on the web, Codex cloud, Jules, or
# any Ubuntu/Debian box). Paste `bash tools/setup/gamedev_env.sh` into the environment's setup
# script. It's idempotent: re-running only fills in what's missing.
#
# Installs:
#   • system packages: Xvfb and Mesa (software OpenGL, for screenshots and Blender renders),
#     ffmpeg (audio and video conversion), unzip, xz-utils, python3-pip
#   • Godot (headless-capable editor binary)   → tools/ci/install_godot.sh   (GODOT_VERSION)
#   • Blender LTS (runs with --background)       → tools/setup/install_blender.sh (BLENDER_VERSION)
#   • optionally the Godot export templates (for web and desktop exports)
# Then builds the Godot import cache and writes GODOT / BLENDER paths to ~/.gamedev_env (and to
# $CLAUDE_ENV_FILE when Claude Code provides one).
#
# Options (environment variables):
#   SKIP_APT=1                 don't touch system packages
#   SKIP_BLENDER=1             skip Blender (~350 MB download, ~1 min)
#   WITH_EXPORT_TEMPLATES=1    also install Godot's export templates (~1 GB)
set -euo pipefail

cd "$(dirname "$0")/../.."
root="$(pwd)"

log() { echo "[gamedev_env] $*" >&2; }

# --- System packages ------------------------------------------------------------------------
if [ "${SKIP_APT:-}" != "1" ] && command -v apt-get >/dev/null 2>&1; then
	sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		if command -v sudo >/dev/null 2>&1; then sudo="sudo"; else log "not root and no sudo: skipping apt"; fi
	fi
	if [ "$(id -u)" -eq 0 ] || [ -n "$sudo" ]; then
		packages=(unzip xz-utils curl ca-certificates python3-pip ffmpeg xvfb xauth
			libgl1 libegl1 libgl1-mesa-dri libglu1-mesa libxi6 libxrender1 libxkbcommon0
			libxxf86vm1 libxfixes3 libsm6 libice6 libfontconfig1)
		missing=()
		for package in "${packages[@]}"; do
			dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
		done
		if [ "${#missing[@]}" -gt 0 ]; then
			log "installing: ${missing[*]}"
			$sudo apt-get update -qq || true
			DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null \
				|| log "some packages failed to install (continuing)"
		fi
	fi
fi

# --- Godot ----------------------------------------------------------------------------------
godot="$(bash tools/ci/install_godot.sh)"
log "Godot: $("$godot" --headless --version 2>/dev/null | head -1)"

if [ "${WITH_EXPORT_TEMPLATES:-}" = "1" ]; then
	version="${GODOT_VERSION:-4.7.1}"
	templates="$HOME/.local/share/godot/export_templates/${version}.stable"
	if [ ! -d "$templates" ]; then
		log "downloading Godot ${version} export templates (~1 GB)..."
		tmp="$(mktemp -d)"
		curl -fsSL --retry 4 -o "$tmp/templates.tpz" \
			"https://github.com/godotengine/godot/releases/download/${version}-stable/Godot_v${version}-stable_export_templates.tpz"
		unzip -q "$tmp/templates.tpz" -d "$tmp"
		mkdir -p "$(dirname "$templates")"
		mv "$tmp/templates" "$templates"
		rm -rf "$tmp"
	fi
	log "export templates: $templates"
fi

# --- Blender --------------------------------------------------------------------------------
blender=""
if [ "${SKIP_BLENDER:-}" != "1" ]; then
	blender="$(bash tools/setup/install_blender.sh)"
	log "Blender: $("$blender" --background --factory-startup --version 2>/dev/null | head -1)"
fi

# --- Import cache and environment -------------------------------------------------------------
"$godot" --headless --path "$root" --import >/dev/null 2>&1 || true

{
	echo "export GODOT=\"$godot\""
	if [ -n "$blender" ]; then echo "export BLENDER=\"$blender\""; fi
} > "$HOME/.gamedev_env"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	cat "$HOME/.gamedev_env" >> "$CLAUDE_ENV_FILE"
fi
grep -q gamedev_env "$HOME/.bashrc" 2>/dev/null || echo '[ -f ~/.gamedev_env ] && . ~/.gamedev_env' >> "$HOME/.bashrc"

log "ready. Tests: bash tools/ci/validate.sh · screenshots: xvfb-run -a \"\$GODOT\" --rendering-method gl_compatibility --rendering-driver opengl3 --path . -- --skip-menu --capture=/tmp/shot.png"
