// Entry for `node --test web/test`: Node 22 takes that argument as a module
// path, not a directory to scan, so this file imports every test file. A glob
// (`node --test 'web/test/*.test.mjs'`) runs them one process each instead.
import { readdirSync } from 'node:fs';

const here = new URL('.', import.meta.url);
for (const name of readdirSync(here).sort()) {
  if (name.endsWith('.test.mjs')) await import(new URL(name, here));
}
