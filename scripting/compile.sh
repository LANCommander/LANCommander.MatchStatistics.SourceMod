#!/usr/bin/env bash
# Compiles every plugin with SourceMod's compiler, warnings as errors.
#
#   SPCOMP=/path/to/spcomp scripting/compile.sh [output-directory]
#
# SPCOMP is the compiler from a SourceMod 1.12 package
# (addons/sourcemod/scripting/spcomp, or spcomp64; spcomp.exe on Windows). Its
# own include/ directory, next to it, supplies SourceMod's includes. The
# output defaults to out/plugins/. Exit code 0 means everything compiled.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/../out/plugins}"
spcomp="${SPCOMP:?Set SPCOMP to the spcomp from a SourceMod 1.12 package}"
sm_include="$(dirname "$spcomp")/include"

mkdir -p "$out"
failed=0

for source in "$here"/*.sp "$here"/modules/*.sp "$here"/integrations/*.sp; do
    name="$(basename "$source" .sp)"

    if ! "$spcomp" "$source" \
        "-i$sm_include" "-i$here/include" "-i$here/include/thirdparty" "-i$here" \
        "-o$out/$name.smx" -E > "$out/$name.log" 2>&1; then
        echo "FAIL  $name"
        sed -n '4,$p' "$out/$name.log"
        failed=1
    else
        echo "OK    $name"
    fi

    rm -f "$out/$name.log"
done

exit $failed
