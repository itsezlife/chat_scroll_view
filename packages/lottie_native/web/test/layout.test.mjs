import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { LAYOUT, MAX_EDGE } from '../chat_lottie_core.mjs';

const header = readFileSync(
  new URL('../../native/include/chat_lottie.h', import.meta.url),
  'utf8',
);

// On wasm32 every scalar the header uses is 4 bytes with 4-byte alignment,
// pointers and size_t included. The offsets are computed here from the C
// declarations, not copied from the module under test.
const wasm32Size = { uint32_t: 4, float: 4, size_t: 4, pointer: 4 };

function structOf(name) {
  const match = new RegExp(`typedef struct \\{([^}]*)\\} ${name};`).exec(header);
  assert.ok(match, `${name} is declared in chat_lottie.h`);
  const fields = [];
  let offset = 0;
  for (const raw of match[1].replace(/\/\*.*?\*\//g, '').split(';')) {
    const line = raw.trim();
    if (line === '') continue;
    const declaration = /^(\w+)\s*(\*?)\s*(\w+)$/.exec(line);
    assert.ok(declaration, `cannot read the field "${line}"`);
    const [, type, star, field] = declaration;
    const size = wasm32Size[star === '*' ? 'pointer' : type];
    assert.ok(size, `no wasm32 size for ${type}`);
    offset = Math.ceil(offset / size) * size;
    fields.push([field, offset]);
    offset += size;
  }
  return { fields: Object.fromEntries(fields), size: offset };
}

const camel = (snake) => snake.replace(/_(\w)/g, (_, c) => c.toUpperCase());

for (const [key, cName] of [
  ['info', 'ChatLottieInfo'],
  ['job', 'ChatLottieJob'],
]) {
  test(`${cName} offsets and size match the header on wasm32`, () => {
    const expected = structOf(cName);
    const actual = { ...LAYOUT[key] };
    const size = actual.size;
    delete actual.size;
    const named = Object.fromEntries(
      Object.entries(expected.fields).map(([f, o]) => [camel(f), o]),
    );
    assert.deepEqual(actual, named);
    assert.equal(size, expected.size);
  });
}

test('the frame edge cap mirrors the header', () => {
  assert.match(header, new RegExp(`edge over ${MAX_EDGE}`));
});
