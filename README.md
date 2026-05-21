# git-lfs-hub/staging

Reusable workflow + scripts that deploy and test a `lfs-server-staging` Worker.

Consumed by [`git-lfs-hub/deploy`](https://github.com/git-lfs-hub/deploy):

- as a **git submodule** at `deploy/staging/` — gives test scripts to CI runners
- as a **reusable workflow** at `git-lfs-hub/staging/.github/workflows/staging.yml@<ref>` — invoked from `deploy/.github/workflows/pr.yml`

## Reusable workflow

`.github/workflows/staging.yml` — `workflow_call`, two jobs:

| Job | What |
|-----|------|
| `deploy` | checks out caller repo at PR head SHA, renders staging vars, sanity-checks Worker name, deploys via `wrangler` |
| `test` (needs `deploy`) | runs `test-docs.sh` (Tier 2) + `test-git-lfs.sh` against the deployed staging Worker |

Both jobs share concurrency group `lfs-server-staging` (queue-depth 1) because they share one Worker resource.

### Caller-side requirements

The workflow takes one input — the caller's existing `GLH_VARS_JSON` — and derives staging values internally by appending `-staging` to `cloudflare.workerName` and `s3.bucket`. **No separate `GLH_STAGING_VARS_JSON` needed.**

| Caller input/secret | Used as | Purpose |
|---------------------|---------|---------|
| `inputs.vars-json` | mutated → `vars.input.json` in both jobs | Caller's `GLH_VARS_JSON` (prod vars.input.json contents); workflow appends `-staging` suffix |
| `secrets.CLOUDFLARE_API_TOKEN` | `deploy` job env | Wrangler deploy auth |
| `secrets.TURBO_TOKEN` | `deploy` job env | Optional Turbo remote cache |
| `secrets.GLH_STAGING_GITHUB_PAT` | `test` job env (`GH_PAT`) | Write on `git-lfs-hub/test`; org-mode requires `read:org` |
| `secrets.GLH_STAGING_LOGIN_SECRET` | `test` job env (`LOGIN_SECRET`) | Must match `LOGIN_SECRET` Worker secret on `lfs-server-staging` |

### Caller example (`deploy/.github/workflows/pr.yml`)

```yaml
staging:
  needs: test
  if: github.event.pull_request.head.repo.full_name == github.repository
  uses: git-lfs-hub/staging/.github/workflows/staging.yml@main
  with:
    vars-json: ${{ vars.GLH_VARS_JSON || secrets.GLH_VARS_JSON }}
  secrets: inherit
```

7 lines.

### What the workflow assumes about the caller repo

Checkout uses `repository: ${{ github.repository }}` — the caller. Then expects:

- `./.github/actions/init` — installs Bun, renders config artifacts via `bun turbo '//#config'`
- `staging/` submodule — provides `test-docs.sh`, `test-git-lfs.sh`, `session-cookie.ts`
- `server/` submodule — provides `server/wrangler.template.jsonc` and source for `wrangler deploy`

## Tests (vitest)

| File | What it covers |
|------|----------------|
| `test-docs.test.ts` | Tier 2: authenticated HTML + assets + unauth 302 redirect |
| `test-git-lfs.test.ts` | Real `git lfs push` against staging Worker to `git-lfs-hub/test` repo |
| `lib.ts` | Shared: typed `vars.json` loader (absolute path), `requireEnv` |

Run from `staging/` cwd:

```sh
bun run test     # bunx vitest run --reporter=github-actions
```

Caller workflow uses `working-directory: staging` + `bun run test`. Tests pull `STAGING_URL`, `DOCS_TITLE`, `LFS_URL` from `../vars.json` (deploy root) via `lib.vars`.

### Caller-side `staging` workspace

Staging is registered as a `bun` workspace in `deploy/package.json`, so root `bun install --frozen-lockfile` installs vitest into `staging/node_modules`. Fork users must add `"staging"` to their `package.json` `workspaces` array.

### Required environment (set by `staging.yml`)

| Variable | Used by | Source |
|----------|---------|--------|
| `GH_PAT` | both tests | caller's `GLH_STAGING_GITHUB_PAT` |
| `LOGIN_SECRET` | `test-docs` | caller's `GLH_STAGING_LOGIN_SECRET` |
| `PR_NUMBER`, `RUN_ID` | `test-git-lfs` | `github.event.pull_request.number`, `github.run_id` |

Tests throw on missing env via `lib.requireEnv` — fail loudly at module load.

### Local smoke run

From a `deploy` checkout with rendered staging `vars.json`:

```sh
export GH_PAT=ghp_...
export LOGIN_SECRET=<64-hex>
export PR_NUMBER=local
export RUN_ID=$(date +%s)

cd staging
bun run test
```

## Cross-repo import

`test-docs.test.ts` imports `encryptCode` from `../server/src/login/utils.ts` (the `server` submodule in `deploy`). `utils.ts` only depends on `jose`, no Workers runtime needed — runs in vitest's default node environment.

If `server/src/login/utils.ts` is moved or its `encryptCode` signature changes, `test-docs.test.ts` must be updated in lockstep.
