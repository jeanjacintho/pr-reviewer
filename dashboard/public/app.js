'use strict';
const REFRESH_MS = 30000;
const state = { repos: [], dirty: false };
const $ = (selector) => document.querySelector(selector);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else if (key in node) node[key] = value;
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(body.error || res.statusText), { errors: body.errors || [] });
  return body;
}

function setStatus(text, kind = '') {
  const status = $('#status');
  status.textContent = text;
  status.className = `status ${kind}`;
}

// Editing is only on once the saved settings are loaded, and off while saving,
// so a partial or stale list can never be sent.
function setEditable(on) {
  $('#editor').disabled = !on;
  $('#save').disabled = !(on && state.dirty);
}

function markDirty() {
  state.dirty = true;
  $('#save').disabled = false;
  setStatus('Unsaved changes', 'dirty');
}

function showErrors(errors) {
  const list = $('#errors');
  list.replaceChildren(...errors.map((message) => el('li', { textContent: message })));
  list.hidden = errors.length === 0;
}

function textField(label, value, onInput, { mono = false, list = '', placeholder = '', hint = '' } = {}) {
  const id = `f${Math.random().toString(36).slice(2)}`;
  const input = el('input', { id, value, placeholder, spellcheck: false, autocomplete: 'off', className: mono ? 'mono' : '' });
  if (list) input.setAttribute('list', list);
  input.addEventListener('input', () => onInput(input.value));
  return el('div', { className: 'field' }, el('label', { htmlFor: id, textContent: label }), input, hint ? el('p', { className: 'hint', textContent: hint }) : '');
}

function usersField(repo) {
  const chips = el('div', { className: 'chips' });
  const draw = () => {
    const add = el('input', { placeholder: 'GitHub login', 'aria-label': `Add trusted user to ${repo.repo}`, autocomplete: 'off', spellcheck: false });
    add.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ',') return;
      event.preventDefault();
      const login = add.value.trim().replace(/^@/, '');
      if (!login || repo.trusted_users.some((known) => known.toLowerCase() === login.toLowerCase())) return;
      repo.trusted_users.push(login);
      markDirty();
      draw();
      chips.querySelector('input').focus();
    });
    chips.replaceChildren(
      ...repo.trusted_users.map((login) =>
        el('span', { className: 'chip' }, login, el('button', {
          type: 'button',
          textContent: '×',
          'aria-label': `Remove ${login}`,
          onclick: () => {
            repo.trusted_users = repo.trusted_users.filter((known) => known !== login);
            markDirty();
            draw();
          },
        }))),
      add,
    );
  };
  draw();
  return el('div', { className: 'field' },
    el('span', { className: 'label', textContent: 'Trusted people' }),
    chips,
    el('p', { className: 'hint', textContent: 'They can start reviews here by commenting a command. Their own pull requests also get the test command run on this Mac, so trust only people whose code you are willing to execute.' }));
}

function repoCard(repo) {
  const enabled = el('input', { type: 'checkbox', checked: repo.enabled, 'aria-label': `Watch ${repo.repo}` });
  const card = el('article', { className: `repo${repo.enabled ? '' : ' off'}` },
    el('div', { className: 'repo-head' },
      el('span', { className: 'repo-name', textContent: repo.repo }),
      el('div', { className: 'toggle' },
        el('label', {}, enabled, ' Watching'),
        el('button', { type: 'button', className: 'quiet', textContent: 'Remove', onclick: () => removeRepo(repo) }))),
    usersField(repo),
    textField('Review model', repo.model, (value) => { repo.model = value; markDirty(); }, { list: 'models', placeholder: 'Default', hint: 'Leave empty to use the Codex default configured on this Mac.' }),
    textField('Test command', repo.test_cmd, (value) => { repo.test_cmd = value; markDirty(); }, { mono: true, placeholder: 'npm ci && npm test', hint: 'Optional. Runs in a throwaway checkout, only for pull requests by trusted people.' }));
  enabled.addEventListener('change', () => {
    repo.enabled = enabled.checked;
    card.classList.toggle('off', !repo.enabled);
    markDirty();
  });
  return card;
}

function renderRepos() {
  const models = [...new Set(state.repos.map((repo) => repo.model).filter(Boolean))];
  $('#models').replaceChildren(...models.map((model) => el('option', { value: model })));
  $('#repos').replaceChildren(...(state.repos.length
    ? state.repos.map(repoCard)
    : [el('p', { className: 'empty', textContent: 'No repositories yet. Add one above to start watching it.' })]));
}

function removeRepo(repo) {
  if (!confirm(`Stop watching ${repo.repo}? This is saved when you press Save changes.`)) return;
  state.repos = state.repos.filter((known) => known !== repo);
  markDirty();
  renderRepos();
}

function addRepo(event) {
  event.preventDefault();
  const input = $('#add-repo');
  const name = input.value.trim();
  if (state.repos.some((known) => known.repo.toLowerCase() === name.toLowerCase())) {
    showErrors([`${name} is already listed`]);
    return;
  }
  showErrors([]);
  state.repos.push({ repo: name, enabled: true, trusted_users: [], model: '', test_cmd: '' });
  input.value = '';
  markDirty();
  renderRepos();
}

// "repos[3].repo is not valid" reads better as "bad name: repo is not valid".
function describeError(message) {
  return message.replace(/^repos\[(\d+)\]\.?/, (_, index) => `${state.repos[index]?.repo || `Entry ${Number(index) + 1}`}: `);
}

async function save() {
  setEditable(false);
  setStatus('Saving…');
  try {
    state.repos = (await api('/api/repos', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ repos: state.repos }) })).repos;
    state.dirty = false;
    showErrors([]);
    renderRepos();
    setEditable(true);
    setStatus('Saved. The bot uses it from its next poll.', 'saved');
  } catch (error) {
    showErrors(error.errors?.length ? error.errors.map(describeError) : [error.message]);
    setEditable(true);
    setStatus('Not saved', 'dirty');
  }
}

function renderActivity({ reviews, log }) {
  $('#reviews').replaceChildren(...(reviews.length
    ? reviews.slice(0, 15).map((review) => el('li', {},
      el('strong', { textContent: `${review.repo}#${review.pr}` }),
      el('span', { className: 'sha', textContent: String(review.sha).slice(0, 7) }),
      el('span', { className: 'when', textContent: new Date(review.at).toLocaleString() })))
    : [el('li', { textContent: 'No reviews yet.' })]));
  const logBox = $('#log');
  const atEnd = logBox.scrollTop + logBox.clientHeight >= logBox.scrollHeight - 8;
  logBox.textContent = log.length ? log.join('\n') : 'Nothing logged yet.';
  if (atEnd) logBox.scrollTop = logBox.scrollHeight;
}

async function refreshActivity() {
  try {
    renderActivity(await api('/api/activity'));
  } catch (error) {
    $('#log').textContent = `Could not load activity: ${error.message}`;
  }
}

async function loadRepos() {
  setEditable(false);
  try {
    state.repos = (await api('/api/repos')).repos;
    $('#load-error').hidden = true;
    renderRepos();
    setEditable(true);
  } catch (error) {
    $('#load-error-text').textContent = `Could not load repositories (${error.message}). Editing stays off so nothing is overwritten.`;
    $('#load-error').hidden = false;
  }
}

async function start() {
  $('#add-form').addEventListener('submit', addRepo);
  $('#save').addEventListener('click', save);
  $('#retry').addEventListener('click', loadRepos);
  $('#refresh').addEventListener('click', refreshActivity);
  window.addEventListener('beforeunload', (event) => { if (state.dirty) event.preventDefault(); });
  await loadRepos();
  await refreshActivity();
  setInterval(refreshActivity, REFRESH_MS);
}

start();
