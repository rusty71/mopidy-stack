#!/usr/bin/env bash
# Check that both Icecast mounts are alive and report what they are serving.
set -uo pipefail

ICECAST=${ICECAST:-http://127.0.0.1:8000}

for mount in low.mp3 high.ogg; do
    printf '%-10s ' "/$mount"
    bytes=$(curl -s --max-time 3 "$ICECAST/$mount" | wc -c)
    if [ "$bytes" -gt 0 ]; then
        printf 'OK (%s bytes in 3s)\n' "$bytes"
    else
        printf 'NO DATA\n'
    fi
done

echo
echo "Mounts known to Icecast:"
curl -s "$ICECAST/status-json.xsl" |
    python3 -c 'import json,sys; d=json.load(sys.stdin)["icestats"]; [print("  ", s["listenurl"]) for s in d.get("source", [])]'
