'use strict';
// Mirrors the checks lib/repos.jq applies when the bot reads repos.json.
const REPO_RE = /^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/;
const LOGIN_RE = /^[A-Za-z0-9-]{1,39}$/;
const MODEL_RE = /^[A-Za-z0-9._:-]{0,64}$/;
const EFFORT_RE = /^[a-z]{0,16}$/;
const ENGINES = ['codex', 'claude'];
const DEPTHS = ['quick', 'deep'];
const MAX_TEST_CMD = 2000;

function checkRepo(value, at, errors) {
  const valid = typeof value === 'string' && REPO_RE.test(value) && !['.', '..'].includes(value.split('/')[1]);
  if (!valid) errors.push(`${at}.repo must look like owner/name`);
  return valid;
}

function checkLogins(value, at, errors) {
  if (!Array.isArray(value)) {
    errors.push(`${at}.trusted_users must be an array`);
    return [];
  }
  const seen = new Set();
  const logins = [];
  value.forEach((login, i) => {
    if (typeof login !== 'string' || !LOGIN_RE.test(login)) {
      errors.push(`${at}.trusted_users[${i}] must be a GitHub login`);
    } else if (!seen.has(login.toLowerCase())) {
      seen.add(login.toLowerCase());
      logins.push(login);
    }
  });
  return logins;
}

function checkText(value, at, errors, { name, pattern, max }) {
  const ok = typeof value === 'string' && value.length <= (max || Infinity) && !value.includes('\0') && (!pattern || pattern.test(value));
  if (!ok) errors.push(`${at}.${name} is not valid`);
  return ok ? value : '';
}

function checkEntry(entry, at, errors) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    errors.push(`${at} must be an object`);
    return null;
  }
  const { enabled = true, trusted_users = [], engine = 'codex', depth = 'quick', model = '', effort = '', test_cmd = '' } = entry;
  checkRepo(entry.repo, at, errors);
  if (typeof enabled !== 'boolean') errors.push(`${at}.enabled must be true or false`);
  if (!ENGINES.includes(engine)) errors.push(`${at}.engine must be one of ${ENGINES.join(', ')}`);
  if (!DEPTHS.includes(depth)) errors.push(`${at}.depth must be one of ${DEPTHS.join(', ')}`);
  return {
    repo: entry.repo,
    enabled,
    trusted_users: checkLogins(trusted_users, at, errors),
    engine,
    depth,
    model: checkText(model, at, errors, { name: 'model', pattern: MODEL_RE }),
    effort: checkText(effort, at, errors, { name: 'effort', pattern: EFFORT_RE }),
    test_cmd: checkText(test_cmd, at, errors, { name: 'test_cmd', max: MAX_TEST_CMD }),
  };
}

function validateRepos(input) {
  if (!input || !Array.isArray(input.repos)) return { ok: false, errors: ['repos must be an array'] };
  const errors = [];
  const seen = new Set();
  const repos = [];
  input.repos.forEach((entry, i) => {
    const at = `repos[${i}]`;
    const clean = checkEntry(entry, at, errors);
    if (!clean) return;
    const key = String(clean.repo).toLowerCase();
    if (seen.has(key)) errors.push(`${at}.repo is listed twice`);
    seen.add(key);
    repos.push(clean);
  });
  return errors.length ? { ok: false, errors } : { ok: true, value: { repos } };
}

module.exports = { validateRepos, ENGINES };
