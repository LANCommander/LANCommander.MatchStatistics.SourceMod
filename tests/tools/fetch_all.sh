#!/usr/bin/env bash
# For each game: SteamCMD into a fresh volume, extract the event files, drop the volume.
# Usage: fetch_all.sh "name:appid:platform" ...
set -u
root=/d/Repositories/LANCommander.SourceMod.MatchStatistics
out="$root/out/gameinfo"
mkdir -p "$out"
docker pull -q python:3.12-slim >/dev/null

for spec in "$@"; do
    IFS=: read -r name app platform <<<"$spec"
    vol="lcsm-gi-$name"
    echo "=== $name ($app, $platform) $(date +%T)"
    force=""
    [ "$platform" = windows ] && force="+@sSteamCmdForcePlatformType windows"

    for attempt in 1 2 3; do
        MSYS_NO_PATHCONV=1 docker run --rm -v "$vol:/data" -v lcsm-steam:/root/Steam --entrypoint bash lccss:latest \
            -c "/opt/steamcmd/steamcmd.sh $force +force_install_dir /data +login anonymous +app_update $app +quit" \
            > "$out/$name.steamcmd.log" 2>&1
        grep -q "Success! App '$app'" "$out/$name.steamcmd.log" && break
        echo "  attempt $attempt failed: $(grep -E 'ERROR|Error' "$out/$name.steamcmd.log" | tail -1)"
    done

    MSYS_NO_PATHCONV=1 docker run --rm -v "$vol:/data:ro" -v "$out:/out" -v "$root/tests/tools:/tools:ro" python:3.12-slim \
        python -I /tools/extract_gameinfo.py /data "/out/$name"
    size=$(MSYS_NO_PATHCONV=1 docker run --rm -v "$vol:/data:ro" busybox du -sh /data | cut -f1)
    echo "  size $size; extracted: $(find "$out/$name" -type f | wc -l) files"
    docker volume rm "$vol" >/dev/null
done
echo "=== done $(date +%T)"
