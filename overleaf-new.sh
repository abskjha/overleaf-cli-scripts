#!/usr/bin/env bash
# overleaf-new.sh — create an Overleaf project and invite collaborators.
#
# Usage:   ./overleaf-new.sh "Project name" [email ...]
# Example: ./overleaf-new.sh "My paper" user1@example.com user2@example.com
#
# Options (environment variables):
#   ROLE=readAndWrite | readOnly     (default: readAndWrite = editor)
#   TEMPLATE=none | example          (default: none = blank project)
#   TAG="name"                       (optional: tag/label on YOUR dashboard;
#                                     created if it doesn't exist; collaborators
#                                     don't see your tags)
#   ENV_FILE=path                    (default: ~/.overleaf-session.env)
#   OVERLEAF_BASE_URL=url            (default: https://www.overleaf.com)
#
# Not affiliated with Overleaf. Uses undocumented internal endpoints; using it
# may violate Overleaf's Terms of Service. Use at your own risk, no warranty.

set -euo pipefail

BASE="${OVERLEAF_BASE_URL:-https://www.overleaf.com}"
ROLE="${ROLE:-readAndWrite}"
TEMPLATE="${TEMPLATE:-none}"
ENV_FILE="${ENV_FILE:-$HOME/.overleaf-session.env}"

# Load the cookie from the env file if it isn't already set
if [[ -z "${OVERLEAF_SESSION:-}" && -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi
[[ -n "${OVERLEAF_SESSION:-}" ]] || { echo "Error: OVERLEAF_SESSION is not set" >&2; exit 1; }
[[ $# -ge 1 && -n "$1" ]] || { echo "Usage: $0 \"Project name\" [email ...]" >&2; exit 1; }

NAME="$1"; shift
COOKIE="overleaf_session2=$OVERLEAF_SESSION"

# Build JSON safely (handles quotes etc. in names): json key1 val1 key2 val2 ...
json() {
  python3 -c 'import json,sys; a=sys.argv[1:]; print(json.dumps(dict(zip(a[::2], a[1::2]))))' "$@"
}

# Read a field from a JSON body; prints nothing if missing or not JSON
field() {
  python3 -c 'import json,sys
try:
    v = json.loads(sys.stdin.read()).get(sys.argv[1])
    print("" if v is None else v)
except Exception:
    pass' "$1"
}

# POST JSON; output = body, then HTTP status on the last line
post() {
  curl -s -b "$COOKIE" \
    -H "X-Csrf-Token: $CSRF" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -w '\n%{http_code}' \
    -d "$2" "$BASE$1"
}

# 1. Check the session and read the CSRF token from the dashboard page
PAGE=$(curl -s -b "$COOKIE" -w '\n%{http_code}' "$BASE/project")
STATUS=$(tail -n1 <<<"$PAGE")
if [[ "$STATUS" != 200 ]]; then
  echo "Error: session invalid (HTTP $STATUS). Get a fresh overleaf_session2 cookie." >&2
  exit 2
fi
CSRF=$(grep -o 'name="ol-csrfToken" content="[^"]*"' <<<"$PAGE" | sed 's/.*content="//;s/"$//' || true)
[[ -n "$CSRF" ]] || { echo "Error: could not find CSRF token on the page" >&2; exit 3; }

# 2. Create the project
RESP=$(post /project/new "$(json projectName "$NAME" template "$TEMPLATE")")
STATUS=$(tail -n1 <<<"$RESP"); BODY=$(sed '$d' <<<"$RESP")
PROJECT_ID=$(field project_id <<<"$BODY")
if [[ "$STATUS" != 200 || -z "$PROJECT_ID" ]]; then
  echo "Error: project creation failed (HTTP $STATUS): $BODY" >&2
  exit 4
fi
echo "Created: \"$NAME\" → $BASE/project/$PROJECT_ID"
FAILED=0

# 3. Optional: add the project to a tag, creating the tag if needed
if [[ -n "${TAG:-}" ]]; then
  TAGS=$(curl -s -b "$COOKIE" -H "Accept: application/json" "$BASE/tag")
  TAG_ID=$(python3 -c 'import json,sys
try:
    for t in json.loads(sys.stdin.read()):
        if t.get("name", "").lower() == sys.argv[1].lower():
            print(t["_id"]); break
except Exception:
    pass' "$TAG" <<<"$TAGS")
  if [[ -z "$TAG_ID" ]]; then
    RESP=$(post /tag "$(json name "$TAG")")
    TAG_ID=$(sed '$d' <<<"$RESP" | field _id)
  fi
  if [[ -n "$TAG_ID" ]]; then
    RESP=$(post "/tag/$TAG_ID/project/$PROJECT_ID" '{}')
    STATUS=$(tail -n1 <<<"$RESP")
    if [[ "$STATUS" == 200 || "$STATUS" == 204 ]]; then
      echo "Tagged: $TAG"
    else
      echo "Tagging failed (HTTP $STATUS)" >&2; FAILED=1
    fi
  else
    echo "Could not find or create tag: $TAG" >&2; FAILED=1
  fi
fi

# 4. Invite each email
for EMAIL in "$@"; do
  if [[ ! "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    echo "Skipped (not an email): $EMAIL" >&2; FAILED=1; continue
  fi
  RESP=$(post "/project/$PROJECT_ID/invite" "$(json email "$EMAIL" privileges "$ROLE")")
  STATUS=$(tail -n1 <<<"$RESP"); BODY=$(sed '$d' <<<"$RESP")
  INVITE=$(field invite <<<"$BODY")
  if [[ "$STATUS" == 200 && -n "$INVITE" ]]; then
    echo "Invited ($ROLE): $EMAIL"
  else
    echo "Invite failed for $EMAIL (HTTP $STATUS): $BODY" >&2
    FAILED=1
  fi
done

exit $FAILED
