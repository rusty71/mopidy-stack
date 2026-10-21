#!/usr/bin/env bash
# Verify that the Qobuz credentials in config/mopidy.conf work.
#
# Usage: bin/check-qobuz.sh
set -uo pipefail

STACK=/home/opencode/mopidy-stack
CONF="$STACK/config/mopidy.conf"

get() { grep -E "^$1 = " "$CONF" | head -1 | sed -E "s/^$1 = //"; }

app_id=$(get app_id)
auth_token=$(get auth_token)
username=$(get username)
password=$(get password)

if [ -n "$auth_token" ]; then
    echo "Using auth_token from the config."
    "$STACK/venv3/bin/python" - "$app_id" "$auth_token" <<'PY'
import sys
import requests
from mopidy_qobuz.client import Client

app_id, token = sys.argv[1], sys.argv[2]
client = Client(app_id, "")
try:
    client.login_with_token(token)
except Exception as e:
    print(f"Auth token rejected: {e}")
    sys.exit(1)
print(f"Auth OK - Qobuz membership: {client.membership}")
PY
    exit $?
fi

if [ -z "$username" ] || [ -z "$password" ]; then
    echo "No Qobuz credentials found in $CONF"
    echo "Run bin/qobuz-login.sh to get an auth token."
    exit 1
fi

"$STACK/venv3/bin/python" - "$username" "$password" "$app_id" "$(get secret)" <<'PY'
import sys
from mopidy_qobuz.client import Client, AuthenticationError, InvalidAppIdError

username, password, app_id, secret = sys.argv[1:5]
client = Client(app_id, secret)
try:
    client.login(username, password)
except AuthenticationError as e:
    print(f"Login failed: {e}")
    print("Note: Qobuz blocks e-mail/password logins since April 2026.")
    print("Run bin/qobuz-login.sh to get an auth token instead.")
    sys.exit(1)
except InvalidAppIdError as e:
    print(f"Invalid app_id: {e}  (run bin/update-qobuz-keys.sh)")
    sys.exit(1)
print(f"Login OK - Qobuz membership: {client.membership}")
PY
