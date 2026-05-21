import { describe, test, expect, beforeAll } from "vitest";
import { $ } from "bun";
import { vars, requireEnv } from "./lib";

const { GH_PAT, PR_NUMBER, RUN_ID } = requireEnv("GH_PAT", "PR_NUMBER", "RUN_ID");
const STAGING_HOST = vars.lfs.server;
const LFS_URL = `https://${STAGING_HOST}/git-lfs-hub/test`;
const BRANCH = `ci/pr-${PR_NUMBER}-${RUN_ID}`;
const FILE = `ci-${RUN_ID}.bin`;
const COMMIT_MSG = `ci: staging test PR #${PR_NUMBER} run ${RUN_ID}`;
const CRED_HELPER = '!f() { echo "username=x-access-token"; echo "password=$GH_PAT"; }; f';

describe("staging LFS push", () => {
  beforeAll(async () => {
    await $`git lfs install`.quiet();
    await $`git clone --quiet https://x-access-token:${GH_PAT}@github.com/git-lfs-hub/test.git test-repo`
      .env({ ...process.env, GIT_LFS_SKIP_SMUDGE: "1" });
    $.cwd("test-repo");
    await $`git config lfs.url ${LFS_URL}`;
    await $`git config credential.https://${STAGING_HOST}.helper ${CRED_HELPER}`;
  });

  test("lfs.url overridden to staging", async () => {
    const url = (await $`git config lfs.url`.text()).trim();
    expect(url).toBe(LFS_URL);
  });

  test("commit fresh LFS-tracked file", async () => {
    await Bun.write(`test-repo/${FILE}`, `ci pr-${PR_NUMBER} run-${RUN_ID} ${new Date().toISOString()}\n`);
    await $`git add ${FILE}`;
    await $`git -c user.email=ci@git-lfs-hub.local -c user.name=lfs-hub-ci commit --quiet -m ${COMMIT_MSG}`;
    const head = (await $`git log -1 --format=${"%h"}`.text()).trim();
    expect(head).toMatch(/^[0-9a-f]+$/);
  });

  test("push branch + LFS objects to staging Worker", async () => {
    const out = await $`git push --porcelain origin HEAD:refs/heads/${BRANCH}`.text();
    expect(out, "push output must reference the new branch").toContain(BRANCH);
  });
});
