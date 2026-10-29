#!/usr/bin/env bash
# set-overleaf-cookie.sh — safely store your Overleaf session cookie.
#
# Usage:
#   ./set-overleaf-cookie.sh                        # save on this machine
#   REMOTE=user@host ./set-overleaf-cookie.sh      # also copy to your server
#
# Options (environment variables):
#   ENV_FILE=path      local file   (default: ~/.overleaf-session.env)
#   REMOTE=user@host   copy to this server over SSH as well
#   REMOTE_FILE=path   file on the server (default: .overleaf-session.env in its home dir)
#
# The cookie is read from a hidden prompt, so it never appears on screen, in
# shell history, or in the command line of any process.
#
# Not affiliated with Overleaf. Uses undocumented internal endpoints; using it
# may violate Overleaf's Terms of Service. Use at your own risk, no warranty.

set -euo pipefail

BASE="${OVERLEAF_BASE_URL:-https://www.overleaf.com}"
ENV_FILE="${ENV_FILE:-$HOME/.overleaf-session.env}"
REMOTE_FILE="${REMOTE_FILE:-.overleaf-session.env}"

# 1. Read the cookie without echoing it
printf 'Paste the overleaf_session2 cookie value (hidden), then press Enter: ' >&2
IFS= read -rs VALUE
echo >&2

# Tidy up common paste variations: whitespace, quotes, "overleaf_session2=" prefix
VALUE="$(printf '%s' "$VALUE" | tr -d '[:space:]')"
VALUE="${VALUE#overleaf_session2=}"
VALUE="${VALUE#\"}"; VALUE="${VALUE%\"}"

if [[ -z "$VALUE" || "$VALUE" =~ [\'\"\;\\] ]]; then
  echo "Error: that doesn't look like a cookie value. Nothing was saved." >&2
  exit 1
fi

# 2. Check it works before saving (cookie passed via stdin, not the command line)
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -K - "$BASE/project" \
  <<<"cookie = \"overleaf_session2=$VALUE\"" || true)
if [[ "$STATUS" != 200 ]]; then
  echo "Error: Overleaf rejected the cookie (HTTP $STATUS). Nothing was saved." >&2
  echo "Make sure you copied the full value of overleaf_session2." >&2
  exit 2
fi
echo "Cookie is valid." >&2

# 3. Save locally: private permissions from the start, replaced atomically
umask 077
TMP="$(mktemp "${ENV_FILE}.XXXXXX")"
printf "OVERLEAF_SESSION='%s'\n" "$VALUE" > "$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "Saved to $ENV_FILE" >&2

# 4. Optionally copy to the server (sent through SSH's encrypted stdin)
if [[ -n "${REMOTE:-}" ]]; then
  printf "OVERLEAF_SESSION='%s'\n" "$VALUE" | ssh "$REMOTE" \
    "umask 077 && cat > '$REMOTE_FILE.tmp' && mv '$REMOTE_FILE.tmp' '$REMOTE_FILE' && chmod 600 '$REMOTE_FILE'"
  echo "Copied to $REMOTE:$REMOTE_FILE" >&2
fi

unset VALUE
