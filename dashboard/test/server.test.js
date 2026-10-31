'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { createServer } = require('../server');

const VALID = { repos: [{ repo: 'o/a', enabled: true, trusted_users: ['alice'], model: '', test_cmd: '' }] };

async function withServer(fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dash-'));
  fs.mkdirSync(path.join(root, 'state'));
  const server = createServer({ root });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  try {
    await fn({ root, port, file: path.join(root, 'repos.json') });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function request(port, { method = 'GET', url = '/', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: url, headers: { Host: `127.0.0.1:${port}`, ...headers } }, (res) => {
      let text = '';
      res.on('data', (chunk) => (text += chunk));
      res.on('end', () => resolve({ status: res.statusCode, body: text ? JSON.parse(text) : null }));
    });
    req.on('error', reject);
    req.end(body);
  });
}

const put = (port, payload, headers = {}) =>
  request(port, { method: 'PUT', url: '/api/repos', headers: { 'Content-Type': 'application/json', ...headers }, body: typeof payload === 'string' ? payload : JSON.stringify(payload) });

test('GET /api/repos returns an empty list when the file is missing', () =>
  withServer(async ({ port }) => {
    const res = await request(port, { url: '/api/repos' });
    assert.deepEqual([res.status, res.body], [200, { repos: [] }]);
  }));

test('PUT /api/repos stores the normalized settings atomically', () =>
  withServer(async ({ port, root, file }) => {
    const res = await put(port, { repos: [{ repo: 'o/a', trusted_users: ['alice'], extra: 1 }] });
    assert.deepEqual([res.status, res.body], [200, VALID]);
    assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), VALID);
    assert.deepEqual(fs.readdirSync(root).filter((name) => name.includes('tmp')), []);
    assert.deepEqual((await request(port, { url: '/api/repos' })).body, VALID);
  }));

test('a failed write keeps the previous settings byte for byte', () =>
  withServer(async ({ port, root, file }) => {
    const before = JSON.stringify(VALID);
    fs.writeFileSync(file, before);
    fs.chmodSync(root, 0o555);
    try {
      const res = await put(port, { repos: [{ repo: 'o/other' }] });
      assert.equal(res.status, 500);
    } finally {
      fs.chmodSync(root, 0o755);
    }
    assert.equal(fs.readFileSync(file, 'utf8'), before);
    assert.deepEqual(fs.readdirSync(root).filter((name) => name.includes('tmp')), []);
  }));

test('invalid settings are rejected and leave the file unchanged', () =>
  withServer(async ({ port, file }) => {
    fs.writeFileSync(file, JSON.stringify(VALID));
    for (const payload of [{ repos: [{ repo: '../r' }] }, { repos: 'x' }, '{not json', '[]']) {
      const res = await put(port, payload);
      assert.equal(res.status, 400, JSON.stringify(payload));
      assert.ok(res.body.errors.length > 0);
    }
    assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), VALID);
  }));

test('requests from foreign pages are refused and change nothing', () =>
  withServer(async ({ port, file }) => {
    const origin = await put(port, VALID, { Origin: 'https://evil.example' });
    assert.equal(origin.status, 403);
    const host = await put(port, VALID, { Host: `evil.example:${port}` });
    assert.equal(host.status, 403);
    assert.equal((await request(port, { url: '/api/repos', headers: { Host: 'evil.example' } })).status, 403);
    assert.equal(fs.existsSync(file), false);
    const own = await put(port, VALID, { Origin: `http://localhost:${port}`, Host: `localhost:${port}` });
    assert.equal(own.status, 200);
  }));

test('PUT needs a JSON content type and a bounded body', () =>
  withServer(async ({ port, file }) => {
    const wrongType = await request(port, { method: 'PUT', url: '/api/repos', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify(VALID) });
    assert.equal(wrongType.status, 415);
    const huge = await put(port, JSON.stringify({ repos: [], pad: 'x'.repeat(70 * 1024) }));
    assert.equal(huge.status, 413);
    assert.equal(fs.existsSync(file), false);
  }));

test('GET /api/repos reports a damaged file instead of crashing', () =>
  withServer(async ({ port, file }) => {
    fs.writeFileSync(file, '{broken');
    const res = await request(port, { url: '/api/repos' });
    assert.equal(res.status, 500);
    assert.match(res.body.error, /repos\.json/);
  }));

test('GET /api/activity lists reviews newest first and the log tail', () =>
  withServer(async ({ port, root }) => {
    const reviewed = { 'o/a#1': { sha: 'aaa', at: '2026-10-30T10:00:00Z' }, 'o/b#22': { sha: 'bbb', at: '2026-10-31T10:00:00Z' } };
    fs.writeFileSync(path.join(root, 'state', 'reviewed.json'), JSON.stringify(reviewed));
    const lines = Array.from({ length: 250 }, (_, i) => `line ${i}`);
    fs.writeFileSync(path.join(root, 'state', 'poll.log'), lines.join('\n') + '\n');
    const res = await request(port, { url: '/api/activity' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.reviews, [
      { repo: 'o/b', pr: 22, sha: 'bbb', at: '2026-10-31T10:00:00Z' },
      { repo: 'o/a', pr: 1, sha: 'aaa', at: '2026-10-30T10:00:00Z' },
    ]);
    assert.equal(res.body.log.length, 200);
    assert.equal(res.body.log[199], 'line 249');
  }));

test('GET /api/activity works with no state yet', () =>
  withServer(async ({ port }) => {
    const res = await request(port, { url: '/api/activity' });
    assert.deepEqual([res.status, res.body], [200, { reviews: [], log: [] }]);
  }));

test('unknown paths are 404 and wrong methods are 405', () =>
  withServer(async ({ port }) => {
    assert.equal((await request(port, { url: '/api/nope' })).status, 404);
    assert.equal((await request(port, { method: 'DELETE', url: '/api/repos' })).status, 405);
    assert.equal((await request(port, { method: 'POST', url: '/api/activity' })).status, 405);
  }));
