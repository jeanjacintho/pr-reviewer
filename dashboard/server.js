'use strict';
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { validateRepos } = require('./validate');

const MAX_BODY = 64 * 1024;
const LOG_LINES = 200;

class HttpError extends Error {
  constructor(status, message, extra) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

function readJsonFile(file, fallback) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(500, `${path.basename(file)} is not valid JSON`);
  }
}

function writeAtomically(file, data) {
  const temporary = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`);
    fs.renameSync(temporary, file);
  } catch (error) {
    fs.rmSync(temporary, { force: true });
    throw error;
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new HttpError(413, 'body too large'));
        req.resume();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function reviews(root) {
  const stored = readJsonFile(path.join(root, 'state', 'reviewed.json'), {});
  return Object.entries(stored)
    .map(([key, value]) => {
      const at = key.lastIndexOf('#');
      return { repo: key.slice(0, at), pr: Number(key.slice(at + 1)), sha: value.sha, at: value.at };
    })
    .sort((a, b) => String(b.at).localeCompare(String(a.at)));
}

function logTail(root) {
  try {
    const lines = fs.readFileSync(path.join(root, 'state', 'poll.log'), 'utf8').split('\n').filter(Boolean);
    return lines.slice(-LOG_LINES);
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

async function putRepos(req, file) {
  if (!/^application\/json\b/i.test(req.headers['content-type'] || '')) throw new HttpError(415, 'content type must be application/json');
  let input;
  try {
    input = JSON.parse(await readBody(req));
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(400, 'invalid settings', { errors: ['body is not valid JSON'] });
  }
  const result = validateRepos(input);
  if (!result.ok) throw new HttpError(400, 'invalid settings', { errors: result.errors });
  writeAtomically(file, result.value);
  return result.value;
}

function createServer({ root }) {
  const reposFile = path.join(root, 'repos.json');
  const routes = {
    '/api/repos': {
      GET: () => readJsonFile(reposFile, { repos: [] }),
      PUT: (req) => putRepos(req, reposFile),
    },
    '/api/activity': { GET: () => ({ reviews: reviews(root), log: logTail(root) }) },
  };

  // A page open in the browser can reach 127.0.0.1; only our own origin may act.
  function sameOrigin(req, port) {
    const hosts = [`127.0.0.1:${port}`, `localhost:${port}`];
    const origin = req.headers.origin;
    return hosts.includes(req.headers.host) && (origin === undefined || hosts.some((host) => origin === `http://${host}`));
  }

  async function handle(req, res) {
    if (!sameOrigin(req, server.address().port)) throw new HttpError(403, 'forbidden');
    const route = routes[new URL(req.url, 'http://localhost').pathname];
    if (!route) throw new HttpError(404, 'not found');
    const action = route[req.method];
    if (!action) throw new HttpError(405, 'method not allowed');
    send(res, 200, await action(req));
  }

  function send(res, status, body) {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(body));
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((error) => {
      const known = error instanceof HttpError;
      if (!known) console.error(error);
      send(res, known ? error.status : 500, { error: known ? error.message : 'internal error', ...(known ? error.extra : {}) });
    });
  });
  return server;
}

if (require.main === module) {
  const root = process.env.PR_REVIEWER_ROOT || path.resolve(__dirname, '..');
  const port = Number(process.env.DASHBOARD_PORT || 4777);
  createServer({ root }).listen(port, '127.0.0.1', () => console.log(`Dashboard on http://127.0.0.1:${port}`));
}

module.exports = { createServer };
