# Git LFS Hub — e2e

[![CI][ci-badge]][gh-wf-href]
[![CodeQL][codeql-badge]][codeql-href]
[![Socket][socket-badge]][socket-href]
[![License][license-badge]][license-href]

The end-to-end test harness that proves each [Git LFS Hub](https://github.com/git-lfs-hub) release works before it ships. A reusable GitHub Actions workflow (`staging.yml`) deploys a throwaway `-staging` Worker, and a vitest suite (`test-docs`, `test-git-lfs`) exercises a real `git lfs push` against it.

For the bigger picture (what the stack does, the deploy flow, the other repos) see the [org overview](https://github.com/git-lfs-hub).

Consumed by [git-lfs-hub/deploy](https://github.com/git-lfs-hub/deploy):

- as a **git submodule** at `deploy/e2e/` — gives test scripts to CI runners
- as a **reusable workflow** at `git-lfs-hub/e2e/.github/workflows/staging.yml@<ref>` — invoked from `deploy/.github/workflows/pr.yml`, re-run as a post-deploy smoke against the production Worker from `deploy/.github/workflows/main.yml`

## Reusable workflow

`.github/workflows/staging.yml` — `workflow_call`, two jobs:

- **`deploy`** — Checks out caller repo at PR head SHA, renders staging vars, sanity-checks Worker name, deploys via `wrangler`.
- **`test`** (needs `deploy`) — Runs `test-docs.test.ts` + `test-git-lfs.test.ts` against the deployed staging Worker.

Both jobs share concurrency group `lfs-server-staging` (queue-depth 1) because they share one Worker resource.

### Caller-side requirements

The workflow takes one input — the caller's existing `GLH_VARS_JSON` — and derives staging values internally by appending `-staging` to `cloudflare.workerName` and `s3.bucket`. **No separate `GLH_STAGING_VARS_JSON` needed.**

- **`inputs.vars-json`** → mutated to `vars.input.json` in both jobs. Caller's `GLH_VARS_JSON` (prod `vars.input.json` contents); workflow appends `-staging` suffix.
- **`secrets.CLOUDFLARE_API_TOKEN`** → `deploy` job env. Wrangler deploy auth.
- **`secrets.TURBO_TOKEN`** → `deploy` job env. Optional Turbo remote cache.
- **`secrets.GLH_STAGING_GITHUB_PAT`** → `test` job env (`GH_PAT`). Write on `git-lfs-hub/test`; org-mode requires `read:org`.
- **`secrets.GLH_STAGING_LOGIN_SECRET`** → `test` job env (`LOGIN_SECRET`). Must match `LOGIN_SECRET` Worker secret on `lfs-server-staging`.

### Caller example (`deploy/.github/workflows/pr.yml`)

```yaml
staging:
  needs: test
  if: github.event.pull_request.head.repo.full_name == github.repository
  uses: git-lfs-hub/e2e/.github/workflows/staging.yml@main
  with:
    vars-json: ${{ vars.GLH_VARS_JSON || secrets.GLH_VARS_JSON }}
  secrets: inherit
```

### What the workflow assumes about the caller repo

Checkout uses `repository: ${{ github.repository }}` — the caller. Then expects:

- `./.github/actions/init` — installs Bun, renders config artifacts via `bun turbo '//#config'`
- `e2e/` submodule — provides `test-docs.test.ts`, `test-git-lfs.test.ts`, `lib.ts`
- `server/` submodule — provides `server/wrangler.template.jsonc` and source for `wrangler deploy`

## Tests (vitest)

- **`test-docs.test.ts`** — Tier 2: authenticated HTML + assets + unauth 302 redirect.
- **`test-git-lfs.test.ts`** — Real `git lfs push` against staging Worker to `git-lfs-hub/test` repo.
- **`lib.ts`** — Shared: typed `vars.json` loader (absolute path), `requireEnv`.

Run from `e2e/` cwd:

```sh
bun run e2e-test
```

Caller workflow uses `working-directory: e2e` + `bun run e2e-test`. Tests pull `STAGING_URL`, `DOCS_TITLE`, `LFS_URL` from `../vars.json` (deploy root) via `lib.vars`.

### Caller-side `e2e` workspace

The harness is registered as a `bun` workspace in `deploy/package.json`, so root `bun install --frozen-lockfile` installs vitest into `e2e/node_modules`. Fork users must add `"e2e"` to their `package.json` `workspaces` array.

### Required environment (set by `staging.yml`)

- **`GH_PAT`** — both tests; from caller's `GLH_STAGING_GITHUB_PAT`.
- **`LOGIN_SECRET`** — `test-docs`; from caller's `GLH_STAGING_LOGIN_SECRET`.
- **`PR_NUMBER`**, **`RUN_ID`** — `test-git-lfs`; from `github.event.pull_request.number`, `github.run_id`.

Tests throw on missing env via `lib.requireEnv` — fail loudly at module load.

### Local smoke run

From a `deploy` checkout with rendered staging `vars.json`:

```sh
export GH_PAT=ghp_...
export LOGIN_SECRET=<64-hex>
export PR_NUMBER=local
export RUN_ID=$(date +%s)

cd e2e
bun run e2e-test
```

## Cross-repo import

`test-docs.test.ts` imports `encryptSession` from `@git-lfs-hub/auth` (the `auth` workspace in `deploy`). The auth package only depends on `jose` and `@octokit/rest`, no Workers runtime needed — runs in vitest's default node environment.

If `@git-lfs-hub/auth`'s `encryptSession` signature changes, `test-docs.test.ts` must be updated in lockstep.

[ci-badge]: https://badgen.net/github/checks/git-lfs-hub/e2e/main?icon=bun&label=CI
[gh-wf-href]: https://github.com/git-lfs-hub/e2e/actions/workflows/main.yml?query=branch%3Amain

[codeql-badge]: https://github.com/git-lfs-hub/e2e/actions/workflows/github-code-scanning/codeql/badge.svg
[codeql-href]: https://github.com/git-lfs-hub/e2e/actions/workflows/github-code-scanning/codeql?query=branch%3Amain

[socket-badge]: https://badgen.net/static/Socket/report/blue?icon=socket
[socket-href]: https://socket.dev/dashboard/org/git-lfs-hub/repo/@git-lfs-hub/e2e

[license-badge]: https://badgen.net/github/license/git-lfs-hub/e2e
[license-href]: LICENSE.md
