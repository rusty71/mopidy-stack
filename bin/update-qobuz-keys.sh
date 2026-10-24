#!/usr/bin/env bash
# Refresh the Qobuz app_id / secret in mopidy.conf from the Qobuz web player.
#
# Qobuz rotates the app credentials used by their web player every now and
# then.  When the Mopidy-Qobuz extension starts failing with
# "Invalid app secret", run this script and restart Mopidy.
#
# The web player bundle contains several app_id/secret pairs, and every
# app_id only works with its own secret.  The script reads them from the
# bundle; they are not stored in this repository.
#
# By default the production pair is used.  Pick another one with:
#
#   bin/update-qobuz-keys.sh --app 377257687
#
set -euo pipefail

STACK=/home/opencode/mopidy-stack
CONF="$STACK/config/mopidy.conf"

app_id=""
while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            app_id="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$app_id" ]; then
    app_id=$("$STACK/venv-tools/bin/python" - <<'PY'
from qobuz_dl.bundle import Bundle
b = Bundle()
print(b.get_app_id())
PY
    )
fi

# The bundle exposes several candidate secrets; keep the one that produces a
# valid request signature (the API answers 401 = signature OK, 400 = invalid).
secret=$("$STACK/venv-tools/bin/python" - "$app_id" <<'PY'
import hashlib
import sys
import time

import requests

app_id = sys.argv[1]
BASE = "https://www.qobuz.com/api.json/0.2"
session = requests.Session()
session.headers.update(
    {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36.",
        "X-App-Id": app_id,
    }
)

from qobuz_dl.bundle import Bundle

candidates = list(Bundle().get_secrets().values())

for secret in candidates:
    unix = time.time()
    track = 156914988
    sig = hashlib.md5(
        f"trackgetFileUrlformat_id6intentstreamtrack_id{track}{unix}{secret}".encode()
    ).hexdigest()
    r = session.get(
        f"{BASE}/track/getFileUrl",
        params={
            "request_ts": unix,
            "request_sig": sig,
            "track_id": track,
            "format_id": 6,
            "intent": "stream",
        },
    )
    if r.status_code == 401:  # signature accepted, login required
        print(secret)
        sys.exit(0)

sys.exit(f"No working secret found for app_id {app_id}")
PY
)

echo "app_id = $app_id"
echo "secret = $secret"

sed -i -E "s|^app_id = .*|app_id = $app_id|; s|^secret = .*|secret = $secret|" "$CONF"

echo "Updated $CONF"
systemctl --user restart mopidy 2>/dev/null || true
