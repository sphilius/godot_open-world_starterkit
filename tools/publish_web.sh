#!/usr/bin/env bash
# Publish the web export (build/web) to the repo's gh-pages branch for GitHub Pages.
#
#   godot --headless --path . --export-release "Web" build/web/index.html
#   bash tools/publish_web.sh
#
# The branch holds only the latest build (a single force-pushed commit), so the repo doesn't
# grow with every export. Single-threaded web builds need no COOP/COEP headers, so plain Pages works.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/web"
remote="$(git -C "$root" remote get-url origin)"
[ -f "$build/index.html" ] || { echo "No export at $build. Export the Web preset first." >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -r "$build"/. "$stage"/
touch "$stage/.nojekyll"                       # serve files as-is (no Jekyll processing)

git -C "$stage" init -q -b gh-pages
git -C "$stage" config core.autocrlf false     # ship the web files byte-exact
git -C "$stage" config user.name "$(git -C "$root" config user.name)"
git -C "$stage" config user.email "$(git -C "$root" config user.email)"
git -C "$stage" add -A
git -C "$stage" commit -q -m "Web build of $(git -C "$root" rev-parse --short HEAD)"
git -C "$stage" push -q -f "$remote" gh-pages
echo "Published build of $(git -C "$root" rev-parse --short HEAD) to gh-pages."
