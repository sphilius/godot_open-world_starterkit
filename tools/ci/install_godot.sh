#!/usr/bin/env bash
# Downloads the official Godot Linux editor binary (it runs headless) once, caches it, and
# prints its path. Used by tools/ci/validate.sh, the CI workflow and the Claude session hook.
#   GODOT_VERSION    default 4.7.1
#   GODOT_CACHE_DIR  default ~/.cache/godot/<version>
set -euo pipefail

version="${GODOT_VERSION:-4.7.1}"
cache_dir="${GODOT_CACHE_DIR:-$HOME/.cache/godot/$version}"
bin="$cache_dir/godot"

if [ ! -x "$bin" ]; then
	name="Godot_v${version}-stable_linux.x86_64"
	url="https://github.com/godotengine/godot/releases/download/${version}-stable/${name}.zip"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	echo "Downloading Godot ${version}..." >&2
	curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/godot.zip" "$url"
	unzip -q "$tmp/godot.zip" -d "$tmp"
	mkdir -p "$cache_dir"
	mv "$tmp/$name" "$bin"
	chmod +x "$bin"
fi

echo "$bin"
