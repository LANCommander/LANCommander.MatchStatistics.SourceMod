#!/usr/bin/env bash
# Lays out a release: the files a server owner copies into the game directory.
#
#   scripting/package.sh <binaries-directory> <plugins-directory> <output-directory>
#
# <binaries-directory> holds the extension builds by preset, as CI downloads
# them: linux-x86/lancommander.ext.so, linux-x64/lancommander.ext.so,
# windows-x86/lancommander.ext.dll, windows-x64/lancommander.ext.dll (any may
# be missing). <plugins-directory> holds the compiled .smx files.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
binaries="${1:?binaries directory}"
plugins="${2:?plugins directory}"
out="${3:?output directory}"

sm="$out/addons/sourcemod"
mkdir -p "$sm/extensions/x64" "$sm/plugins" "$sm/configs" "$sm/scripting/include"

copy_if_present() {
    if [ -f "$1" ]; then cp "$1" "$2"; else echo "note: $1 not built; left out"; fi
}

# SourceMod loads 32-bit extensions from extensions/ and 64-bit ones from extensions/x64/.
copy_if_present "$binaries/linux-x86/lancommander.ext.so"    "$sm/extensions/"
copy_if_present "$binaries/windows-x86/lancommander.ext.dll" "$sm/extensions/"
copy_if_present "$binaries/linux-x64/lancommander.ext.so"    "$sm/extensions/x64/"
copy_if_present "$binaries/windows-x64/lancommander.ext.dll" "$sm/extensions/x64/"

# Game modules go in plugins/disabled/: the core plugin loads the one for the
# running game. In plugins/ every other game's module would log a load error.
mkdir -p "$sm/plugins/disabled"
for plugin in "$plugins"/*.smx; do
    name="$(basename "$plugin" .smx)"
    if [ -f "$here/modules/$name.sp" ]; then
        cp "$plugin" "$sm/plugins/disabled/"
    else
        cp "$plugin" "$sm/plugins/"
    fi
done
cp "$here/../configs/lancommander_events.cfg" "$sm/configs/"

# The sources, as SourceMod packages ship them, for anyone building a module.
cp "$here"/*.sp "$sm/scripting/"
cp -r "$here/lancommander_stats" "$here/modules" "$here/integrations" "$sm/scripting/"
cp "$here/include/lancommander.inc" "$here/include/lancommander_stats.inc" "$sm/scripting/include/"

cp "$here/../README.md" "$here/../LICENSE" "$out/"

echo "Packaged into $out"
