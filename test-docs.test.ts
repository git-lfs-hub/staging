import { describe, test, expect, beforeAll } from "vitest";
import { encryptSession } from "@git-lfs-hub/auth";
import { vars, requireEnv } from "./lib";

const { GH_PAT, LOGIN_SECRET } = requireEnv("GH_PAT", "LOGIN_SECRET");
const BASE_URL = `https://${vars.lfs.server}`;
const DOCS_TITLE = vars.title;

describe("e2e docs", () => {
  let Cookie: string;

  beforeAll(async () => {
    const cookieValue = await encryptSession({ token: GH_PAT }, LOGIN_SECRET, 86400);
    expect(cookieValue, "encryptSession returned empty").toBeTruthy();
    Cookie = `gh_session_v2=${cookieValue}`;
  });

  async function get(path: string, withCookie: boolean) {
    const r = await fetch(`${BASE_URL}${path}`, {
      headers: withCookie ? { Cookie } : {},
      redirect: "manual",
    });
    return { status: r.status, body: await r.text() };
  }

  test(`GET / with session → 200 + contains '${DOCS_TITLE}'`, async () => {
    const { status, body } = await get("/", true);
    expect(status, body.split("\n").slice(0, 50).join("\n")).toBe(200);
    expect(body).toContain(DOCS_TITLE);
  });

  test.each(["/tools/git-lfs/", "/assets/css/docmd-main.css"])(
    "GET %s with session → 200",
    async (path) => {
      const { status } = await get(path, true);
      expect(status).toBe(200);
    },
  );

  test("GET / without cookie → 302 (auth must redirect)", async () => {
    const { status } = await get("/", false);
    expect(status, "200 means auth is bypassed").toBe(302);
  });
});
