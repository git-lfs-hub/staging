#!/usr/bin/env bash
set -euo pipefail

: "${GH_PAT:?}"
: "${LOGIN_SECRET:?}"

STAGING_URL="https://$(jq -r '.lfs.server' vars.json)"
DOCS_TITLE="$(jq -r '.title' vars.json)"

pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; exit 1; }
step() { printf '\n› %s\n' "$1"; }

printf 'STAGING_URL=%s\nDOCS_TITLE=%s\n' "$STAGING_URL" "$DOCS_TITLE"

step "Mint session cookie"
COOKIE="$(bun staging/mint-session-cookie.ts)" || fail "mint-session-cookie.ts failed"
[ -n "$COOKIE" ] || fail "empty cookie"
AUTH_HEADER="Cookie: gh_session_v2=${COOKIE}"
pass "cookie minted (${#COOKIE} bytes)"

step "GET / with valid session — expect 200 + DOCS_TITLE"
body_file="$(mktemp)"
code="$(curl -sS -H "$AUTH_HEADER" -o "$body_file" -w '%{http_code}' "$STAGING_URL/")"
if [ "$code" != "200" ]; then
  echo "--- response body (first 50 lines) ---" >&2
  head -50 "$body_file" >&2
  fail "expected 200, got $code for $STAGING_URL/"
fi
if ! grep -q "$DOCS_TITLE" "$body_file"; then
  echo "--- response body (first 50 lines) ---" >&2
  head -50 "$body_file" >&2
  fail "DOCS_TITLE '$DOCS_TITLE' not in body of $STAGING_URL/"
fi
pass "200 OK, body contains '$DOCS_TITLE'"

step "GET /tools/git-lfs/ with session — expect 200"
code="$(curl -sS -H "$AUTH_HEADER" -o /dev/null -w '%{http_code}' "$STAGING_URL/tools/git-lfs/")"
[ "$code" = "200" ] || fail "expected 200, got $code for $STAGING_URL/tools/git-lfs/"
pass "200 OK"

step "GET /assets/css/docmd-main.css with session — expect 200"
code="$(curl -sS -H "$AUTH_HEADER" -o /dev/null -w '%{http_code}' "$STAGING_URL/assets/css/docmd-main.css")"
[ "$code" = "200" ] || fail "expected 200, got $code for $STAGING_URL/assets/css/docmd-main.css"
pass "200 OK"

step "GET / without cookie — expect 302"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$STAGING_URL/")"
[ "$code" = "302" ] || fail "expected 302 (unauthenticated redirect), got $code — auth may be bypassed"
pass "302 redirect"

printf '\nAll docs staging checks passed.\n'
