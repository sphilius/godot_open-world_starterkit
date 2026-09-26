#!/usr/bin/env bash
# Downloads the official Blender Linux build (it runs headless with --background) once, caches
# it, and prints the path to the binary. Used by tools/setup/gamedev_env.sh; M2 art scripts call
# it to find Blender. On Windows or macOS, install Blender normally instead.
#   BLENDER_VERSION    default 4.5.14 (4.5 LTS)
#   BLENDER_CACHE_DIR  default ~/.cache/blender/<version>
set -euo pipefail

version="${BLENDER_VERSION:-4.5.14}"
series="${version%.*}"                                  # 4.5.14 -> 4.5
cache_dir="${BLENDER_CACHE_DIR:-$HOME/.cache/blender/$version}"
bin="$cache_dir/blender"

if [ ! -x "$bin" ]; then
	name="blender-${version}-linux-x64"
	url="https://download.blender.org/release/Blender${series}/${name}.tar.xz"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	echo "Downloading Blender ${version} (~350 MB)..." >&2
	curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/blender.tar.xz" "$url"
	tar -xJf "$tmp/blender.tar.xz" -C "$tmp"
	mkdir -p "$(dirname "$cache_dir")"
	rm -rf "$cache_dir"
	mv "$tmp/$name" "$cache_dir"
fi

echo "$bin"
