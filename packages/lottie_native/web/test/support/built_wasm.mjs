// Builds both wasm files once per process through the real build tool, so the
// tests run over what a host gets. Without cargo, the wasm Rust target or dart
// the build cannot run: `builtWasm()` then returns `{skip: reason}` and the
// tests skip with that message instead of failing.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const packageRoot = new URL('../../../', import.meta.url).pathname;

let built;

/** The absolute path of `dart` on PATH, or null. */
export function findDart() {
  return (
    (process.env.PATH ?? '')
      .split(':')
      .map((dir) => join(dir, 'dart'))
      .find((path) => existsSync(path)) ?? null
  );
}

export function runBuildTool(out, env = process.env) {
  return spawnSync(findDart(), ['native/tool/build_web.dart', '--out', out], {
    cwd: packageRoot,
    env,
    encoding: 'utf8',
  });
}

export function builtWasm() {
  if (built) return built;
  if (!findDart()) return (built = { skip: 'dart is not on PATH' });
  const out = mkdtempSync(join(tmpdir(), 'chat_lottie_web_'));
  const run = runBuildTool(out);
  if (run.status === 0) {
    built = { dir: out };
  } else if (/cargo was not found|rustup target add/.test(run.stdout + run.stderr)) {
    built = { skip: `cannot build the wasm: ${(run.stdout + run.stderr).trim().split('\n')[0]}` };
  } else {
    throw new Error(`build_web.dart failed (${run.status}):\n${run.stdout}\n${run.stderr}`);
  }
  return built;
}
