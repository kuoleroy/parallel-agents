import assert from 'node:assert/strict';
import { parseQuery, search } from '../search.js';

assert.equal(
  parseQuery({ q: null, page: 'abc' }).ok,
  false,
  'page=abc 必须判非法：契约规定不静默回落到 1',
);
assert.equal(parseQuery({ q: null, page: '0' }).ok, false, 'page=0 必须判非法');
assert.equal(parseQuery({ q: null, page: '2' }).ok, true, 'page=2 合法');
assert.deepEqual(search({ q: 'abc', page: 2 }), { items: [], total: 0, q: 'abc', page: 2 });

console.log('契约测试通过: 非法分页返回 400，不再静默回落');
