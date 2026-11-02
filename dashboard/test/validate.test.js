'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { validateRepos } = require('../validate');

const entry = (extra) => ({ repo: 'o/a', ...extra });
const check = (repos) => validateRepos({ repos });

test('fills defaults and keeps only known fields', () => {
  const result = check([entry({ junk: 1 })]);
  assert.deepEqual(result, {
    ok: true,
    value: { repos: [{ repo: 'o/a', enabled: true, trusted_users: [], engine: 'codex', depth: 'quick', model: '', effort: '', test_cmd: '' }] },
  });
});

test('accepts a complete entry and dedupes logins ignoring case', () => {
  const result = check([entry({ enabled: false, trusted_users: ['Alice', 'alice', 'bob-1'], model: 'gpt-5.1:x', test_cmd: 'npm ci && npm test' })]);
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.repos[0].trusted_users, ['Alice', 'bob-1']);
  assert.equal(result.value.repos[0].enabled, false);
});

test('rejects bad repo names, including path traversal', () => {
  for (const repo of ['', 'noslash', '../r', 'o/..', 'o/.', 'a b/c', 'o/a/b', 5, undefined]) {
    assert.equal(check([{ repo }]).ok, false, String(repo));
  }
});

test('rejects bad logins, models and types', () => {
  const bad = [
    { trusted_users: 'alice' },
    { trusted_users: { x: 'alice' } },
    { trusted_users: ['al ice'] },
    { trusted_users: ['-'.repeat(40)] },
    { trusted_users: [''] },
    { model: 'bad model;rm' },
    { model: 'x'.repeat(65) },
    { model: 5 },
    { test_cmd: 5 },
    { test_cmd: 'x'.repeat(2001) },
    { test_cmd: 'a\0b' },
    { enabled: 'yes' },
    { engine: 'other-cli' },
    { engine: 5 },
    { effort: 'High' },
    { effort: 'high; rm' },
    { effort: 'x'.repeat(17) },
    { depth: "thorough" },
    { depth: 5 },
    { depth: null },
    { depth: false },
    { engine: null },
    { depth: "Deep" },
  ];
  for (const extra of bad) assert.equal(check([entry(extra)]).ok, false, JSON.stringify(extra));
});

test('keeps a chosen engine and effort', () => {
  const result = check([entry({ engine: 'claude', model: 'opus', effort: 'high' })]);
  assert.equal(result.ok, true);
  assert.deepEqual([result.value.repos[0].engine, result.value.repos[0].model, result.value.repos[0].effort], ['claude', 'opus', 'high']);
});

test('defaults depth to quick and keeps deep', () => {
  assert.equal(check([entry()]).value.repos[0].depth, 'quick');
  assert.equal(check([entry({ depth: 'deep' })]).value.repos[0].depth, 'deep');
});

test('rejects duplicate repos ignoring case and non-array input', () => {
  assert.equal(check([entry(), { repo: 'O/A' }]).ok, false);
  assert.equal(validateRepos({}).ok, false);
  assert.equal(validateRepos(null).ok, false);
  assert.equal(validateRepos({ repos: {} }).ok, false);
});

test('reports every problem with its position', () => {
  const result = check([{ repo: 'bad' }, entry({ model: '!' })]);
  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 2);
  assert.match(result.errors[0], /repos\[0\]\.repo/);
  assert.match(result.errors[1], /repos\[1\]\.model/);
});
