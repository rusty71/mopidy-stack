#!/usr/bin/env bash
# Log in to Qobuz and store an auth token in the Mopidy config.
#
# Qobuz blocks programmatic e-mail/password logins since April 2026, so this
# uses the browser OAuth flow: a local web server catches the redirect and
# exchanges the code for an auth token.
#
# Usage:
#   bin/qobuz-login.sh              # opens a browser, log in there
#   bin/qobuz-login.sh --token <t>  # token copied from the web player
set -euo pipefail

STACK=/home/opencode/mopidy-stack

exec "$STACK/venv-tools/bin/python" "$STACK/bin/qobuz-login.py" "$@"
