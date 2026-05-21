import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

export type Vars = {
  title: string;
  lfs: { server: string };
};

// Resolve vars.json at deploy root (parent of e2e/), independent of CWD.
const e2eDir = dirname(fileURLToPath(import.meta.url));
const varsPath = join(e2eDir, "..", "vars.json");
export const vars = (await Bun.file(varsPath).json()) as Vars;

export function requireEnv<K extends string>(...names: K[]): Record<K, string> {
  const out = {} as Record<K, string>;
  const missing: K[] = [];
  for (const n of names) {
    const v = process.env[n];
    if (v) out[n] = v;
    else missing.push(n);
  }
  if (missing.length) throw new Error(`required env: ${missing.join(", ")}`);
  return out;
}
