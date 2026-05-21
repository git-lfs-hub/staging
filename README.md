# git-lfs-hub/staging

Reusable workflows + scripts that deploy and test a `lfs-server-staging` Worker.

Consumed by [`git-lfs-hub/deploy`](https://github.com/git-lfs-hub/deploy):

- as a **git submodule** at `deploy/staging/` — gives the test scripts to CI runners
- as **reusable workflows** at `git-lfs-hub/staging/.github/workflows/*.yml@main` — invoked from `deploy/.github/workflows/pr.yml`

## Reusable workflows

| Workflow | Purpose |
|----------|---------|
| `.github/workflows/deploy.yml` | `workflow_call` — checks out caller repo at `inputs.ref`, renders staging vars, sanity-checks Worker name, deploys via `wrangler` |
| `.github/workflows/test.yml` | `workflow_call` — runs `docs-test.sh` (Tier 2) + `lfs-push-test.sh` against the deployed staging Worker |

Both workflows check out the **caller** repo (`${{ github.repository }}`) and rely on its `./.github/actions/init` to install Bun and render config.

### Inputs

| Workflow | Input | Type | From |
|----------|-------|------|------|
| `deploy.yml` | `ref` | string | `github.event.pull_request.head.sha` |
| `deploy.yml` | `vars-json` | string | `GLH_STAGING_VARS_JSON` (variable or secret) |
| `test.yml` | `ref` | string | same |
| `test.yml` | `vars-json` | string | same |
| `test.yml` | `pr-number` | number | `github.event.pull_request.number` |
| `test.yml` | `run-id` | number | `github.run_id` |

### Secrets

| Workflow | Secret | Source |
|----------|--------|--------|
| `deploy.yml` | `CLOUDFLARE_API_TOKEN` | required |
| `deploy.yml` | `TURBO_TOKEN` | optional |
| `test.yml` | `GH_PAT` | `GLH_STAGING_GITHUB_PAT` |
| `test.yml` | `LOGIN_SECRET` | `GLH_STAGING_LOGIN_SECRET` (must match Worker secret) |

### Caller example

```yaml
deploy-staging:
  needs: test
  if: github.event.pull_request.head.repo.full_name == github.repository
  concurrency:
    group: lfs-server-staging
    cancel-in-progress: false
  uses: git-lfs-hub/staging/.github/workflows/deploy.yml@main
  with:
    ref: ${{ github.event.pull_request.head.sha }}
    vars-json: ${{ vars.GLH_STAGING_VARS_JSON || secrets.GLH_STAGING_VARS_JSON }}
  secrets:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
```

Concurrency is declared at the **caller** level (resource is the shared `lfs-server-staging` Worker; both `deploy-staging` and `staging-test` callers must share the same group).

## Scripts

| File | Run by | What it does |
|------|--------|---------------|
| `mint-session-cookie.ts` | `docs-test.sh` | Encrypts `{ token: GH_PAT }` with `LOGIN_SECRET` → `gh_session_v2` cookie value |
| `docs-test.sh` | `test.yml` reusable workflow | Tier 2: authenticated HTML + assets + unauth 302 redirect |
| `lfs-push-test.sh` | same | Real `git lfs push` against staging Worker to `git-lfs-hub/test` repo |

### Required environment (set by `test.yml`)

| Variable | Used by | Source |
|----------|---------|--------|
| `STAGING_URL` | `docs-test.sh` | `https://${vars.lfs.server}` from rendered `vars.json` |
| `DOCS_TITLE` | `docs-test.sh` | `vars.title` from rendered `vars.json` |
| `LFS_URL` | `lfs-push-test.sh` | `${STAGING_URL}/git-lfs-hub/test` |
| `GH_PAT` | both | `secrets.GH_PAT` (= caller's `GLH_STAGING_GITHUB_PAT`) |
| `LOGIN_SECRET` | `docs-test.sh` | `secrets.LOGIN_SECRET` (= caller's `GLH_STAGING_LOGIN_SECRET`) |
| `PR_NUMBER`, `RUN_ID` | `lfs-push-test.sh` | `inputs.pr-number`, `inputs.run-id` |

### Local smoke run

From a `deploy` checkout with submodules:

```sh
export STAGING_URL=https://lfs-server-staging.pasha-1dc.workers.dev
export DOCS_TITLE="Git LFS Hub Hub"   # whatever vars.json `title` renders to
export GH_PAT=ghp_...
export LOGIN_SECRET=<64-hex>

./staging/docs-test.sh

export LFS_URL="$STAGING_URL/git-lfs-hub/test"
export PR_NUMBER=local
export RUN_ID=$(date +%s)
./staging/lfs-push-test.sh
```

## Cross-repo import

`mint-session-cookie.ts` imports `encryptCode` from `../server/src/login/utils.ts` (the `server` submodule in `deploy`). It runs under Bun on a CI runner; `utils.ts` only depends on `jose`, no Workers runtime needed.

If `server/src/login/utils.ts` is moved or its `encryptCode` signature changes, this script must be updated in lockstep.
