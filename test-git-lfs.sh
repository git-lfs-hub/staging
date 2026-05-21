#!/usr/bin/env bash
set -euo pipefail

: "${GH_PAT:?}"
: "${PR_NUMBER:?}"
: "${RUN_ID:?}"

export GH_PAT  # credential helper subprocess reads from env

STAGING_HOST="$(jq -r '.lfs.server' vars.json)"
LFS_URL="https://${STAGING_HOST}/git-lfs-hub/test"

# https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
step()   { printf '\n› %s\n' "$1"; }
pass()   { printf '  ✓ %s\n' "$1"; }
fail()   { printf '::error title=lfs-push-test::%s\n' "$1"; exit 1; }
notice() { printf '::notice title=lfs-push-test::%s\n' "$1"; }

BRANCH="ci/pr-${PR_NUMBER}-${RUN_ID}"
FILE="ci-${RUN_ID}.bin"
COMMIT_MSG="ci: staging test PR #${PR_NUMBER} run ${RUN_ID}"

printf 'LFS_URL=%s\nSTAGING_HOST=%s\nBRANCH=%s\nFILE=%s\n' \
  "$LFS_URL" "$STAGING_HOST" "$BRANCH" "$FILE"

step "Install git-lfs hooks"
git lfs install >/dev/null || fail "git lfs install failed"
pass "git-lfs hooks installed"

step "Clone git-lfs-hub/test (skip smudge)"
GIT_LFS_SKIP_SMUDGE=1 git clone --quiet \
  "https://x-access-token:${GH_PAT}@github.com/git-lfs-hub/test.git" test-repo \
  || fail "git clone failed"
cd test-repo
pass "cloned into test-repo"

step "Override lfs.url to staging + register credential helper"
git config lfs.url "$LFS_URL"
git config "credential.https://${STAGING_HOST}.helper" \
  '!f() { echo "username=x-access-token"; echo "password=$GH_PAT"; }; f'
pass "lfs.url=$(git config lfs.url)"

step "Write fresh LFS-tracked file"
printf 'ci pr-%s run-%s %s\n' "$PR_NUMBER" "$RUN_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$FILE"
git add "$FILE"
git diff --cached --stat | sed 's/^/    /'
pass "staged $FILE"

step "Commit"
git -c user.email=ci@git-lfs-hub.local -c user.name="lfs-hub-ci" \
  commit --quiet -m "$COMMIT_MSG" \
  || fail "git commit failed"
pass "committed: $(git log -1 --format='%h %s')"

step "Push branch + LFS objects to staging Worker"
if ! git push --porcelain origin "HEAD:refs/heads/${BRANCH}" 2>&1 | sed 's/^/    /'; then
  fail "git push failed — staging LFS Worker may have rejected upload"
fi
pass "pushed $BRANCH; LFS object uploaded via $STAGING_HOST"

notice "All LFS push staging checks passed."
