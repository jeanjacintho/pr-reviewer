'use strict';
// Rules mirror dashboard/validate.js for instant feedback; the server still decides.
const REPO_RE = /^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/;
const LOGIN_RE = /^[A-Za-z0-9-]{1,39}$/;
const MODEL_RE = /^[A-Za-z0-9._:-]{0,64}$/;
const REFRESH_MS = 30000;
const WEEK_MS = 7 * 24 * 3600 * 1000;

const state = {
  repos: [],
  savedRepos: [],
  selected: '',
  loaded: false,
  saving: false,
  errors: [],
  errorRepos: new Set(),
  activity: { reviews: [], log: [] },
  activityAt: 0,
  activityError: '',
};
// Screen-only choices that are not saved: a model mode picked before typing a
// name, a tests switch turned on before typing a command, a command parked
// while tests are off.
const customModel = new WeakSet();
const testsDraft = new WeakSet();
const parkedCommands = new WeakMap();

const $ = (selector) => document.querySelector(selector);
const key = (name) => String(name).toLowerCase();
const clone = (value) => JSON.parse(JSON.stringify(value));

const ICONS = {
  logo: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M6 8.5v7M18 15.5V11a4 4 0 0 0-4-4h-4"/><path d="m12 4.5-2.5 2.5L12 9.5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-6.4A8 8 0 1 1 21 12z"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
  flask: '<path d="M9 3h6M10 3v6L4.5 19a1.5 1.5 0 0 0 1.3 2h12.4a1.5 1.5 0 0 0 1.3-2L14 9V3"/><path d="M7 15h10"/>',
  spark: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 10h4v4h-4zM9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  external: '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6"/>',
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-1"/>',
};

const NODE_PROPS = new Set(['className', 'textContent', 'value', 'checked', 'disabled', 'type', 'href', 'target', 'rel', 'title', 'placeholder', 'id', 'dateTime', 'htmlFor', 'spellcheck', 'autocomplete']);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(props)) {
    if (value === undefined || value === null) continue;
    if (name.startsWith('on')) node.addEventListener(name.slice(2), value);
    else if (NODE_PROPS.has(name)) node[name] = value;
    else node.setAttribute(name, value);
  }
  node.append(...children.filter((child) => child !== null && child !== undefined && child !== false && child !== ''));
  return node;
}

function icon(name, size = '') {
  const span = el('span', { className: `icon ${size}`, 'aria-hidden': 'true' });
  // Only fixed strings from ICONS are ever parsed here.
  span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;
  return span;
}

function avatar(name, size = '') {
  let hash = 0;
  for (const char of key(name)) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return el('span', { className: `avatar av-${(hash % 8) + 1} ${size}`, textContent: (String(name)[0] || '?').toUpperCase(), 'aria-hidden': 'true' });
}

const relative = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
const UNITS = [[60, 'second', 1], [3600, 'minute', 60], [86400, 'hour', 3600], [604800, 'day', 86400], [2629800, 'week', 604800], [Infinity, 'month', 2629800]];

function ago(when) {
  const seconds = (new Date(when).getTime() - Date.now()) / 1000;
  if (!Number.isFinite(seconds)) return '';
  if (Math.abs(seconds) < 30) return 'just now';
  const [, unit, size] = UNITS.find(([limit]) => Math.abs(seconds) < limit);
  return relative.format(Math.round(seconds / size), unit);
}

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(body.error || res.statusText), { errors: body.errors || [] });
  return body;
}

let toastTimer;
function toast(message, action) {
  const box = $('#toast');
  const parts = [icon(action ? 'info' : 'check'), el('span', { textContent: message })];
  if (action) parts.push(el('button', { type: 'button', className: 'btn ghost sm', onclick: () => { box.hidden = true; action.run(); } }, icon('undo', 'sm'), action.label));
  box.replaceChildren(...parts);
  box.hidden = false;
  box.classList.remove('show');
  void box.offsetWidth;
  box.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, action ? 8000 : 4500);
}

/* ---------- Change tracking ---------- */

function savedMap() {
  return new Map(state.savedRepos.map((repo) => [key(repo.repo), JSON.stringify(repo)]));
}

function changeSummary() {
  const saved = savedMap();
  let added = 0;
  let edited = 0;
  for (const repo of state.repos) {
    const before = saved.get(key(repo.repo));
    if (before === undefined) added += 1;
    else if (before !== JSON.stringify(repo)) edited += 1;
    saved.delete(key(repo.repo));
  }
  return { added, edited, removed: saved.size };
}

function repoBadge(repo, saved) {
  if (state.errorRepos.has(key(repo.repo))) return { kind: 'error', text: 'Check' };
  const before = saved.get(key(repo.repo));
  if (before === undefined) return { kind: 'new', text: 'New' };
  if (before !== JSON.stringify(repo)) return { kind: 'edited', text: 'Edited' };
  return null;
}

function selectedRepo() {
  const repo = state.repos.find((candidate) => key(candidate.repo) === state.selected) || state.repos[0];
  state.selected = repo ? key(repo.repo) : '';
  return repo;
}

function select(name) {
  state.selected = key(name);
  renderList();
  renderDetail();
  if (matchMedia('(max-width: 960px)').matches) $('#detail').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// Something in a repository changed: refresh everything except the open form,
// so the field being typed in keeps its focus.
function changed() {
  renderStats();
  renderList();
  renderSavebar();
  renderModels();
}

function setEditable(on) {
  $('#editor').disabled = !on;
  renderSavebar();
}

function focusId(id) {
  const target = document.getElementById(id);
  if (target) target.focus();
}

/* ---------- Overview ---------- */

function stat(iconName, label, value, note) {
  return el('div', { className: 'stat' },
    el('span', { className: 'stat-icon' }, icon(iconName)),
    el('div', {}, el('div', { className: 'stat-label', textContent: label }), el('div', { className: 'stat-value', textContent: value }), el('div', { className: 'stat-note', textContent: note })));
}

function renderStats() {
  const watching = state.repos.filter((repo) => repo.enabled).length;
  const people = new Set(state.repos.flatMap((repo) => repo.trusted_users.map(key))).size;
  const reviews = state.activity.reviews;
  const recent = reviews.filter((review) => Date.now() - new Date(review.at).getTime() < WEEK_MS).length;
  const tested = state.repos.filter((repo) => repo.test_cmd).length;
  const known = state.loaded;
  $('#stats').replaceChildren(
    stat('eye', 'Watching', known ? String(watching) : '–', known ? `of ${state.repos.length} ${state.repos.length === 1 ? 'repository' : 'repositories'}` : 'loading'),
    stat('users', 'Trusted people', known ? String(people) : '–', 'across all repositories'),
    stat('chat', 'Reviews this week', String(recent), reviews[0] ? `last one ${ago(reviews[0].at)}` : 'none yet'),
    stat('flask', 'Run tests', known ? String(tested) : '–', tested === 1 ? 'repository runs tests' : 'repositories run tests'));
}

/* ---------- Repository list ---------- */

function repoMeta(repo) {
  if (!repo.enabled) return 'Paused';
  const people = repo.trusted_users.length;
  return [people ? `${people} trusted` : 'Nobody trusted yet', repo.test_cmd && 'tests', repo.model].filter(Boolean).join(' · ');
}

function renderList() {
  const list = $('#repo-list');
  $('#repo-count').textContent = state.loaded ? String(state.repos.length) : '';
  if (!state.loaded) {
    list.replaceChildren(...[1, 2, 3].map(() => el('div', { className: 'repo-item skeleton' })));
    return;
  }
  if (!state.repos.length) {
    list.replaceChildren(el('p', { className: 'list-empty', textContent: 'No repositories yet. Add the first one below.' }));
    return;
  }
  const current = selectedRepo();
  const saved = savedMap();
  list.replaceChildren(...state.repos.map((repo) => {
    const [owner, name] = repo.repo.split('/');
    const badge = repoBadge(repo, saved);
    return el('button', {
      type: 'button',
      className: `repo-item${repo === current ? ' selected' : ''}${repo.enabled ? '' : ' paused'}`,
      'aria-current': String(repo === current),
      onclick: () => select(repo.repo),
    },
    avatar(owner),
    el('span', { className: 'repo-item-text' },
      el('span', { className: 'repo-item-name' }, el('span', { className: 'muted', textContent: `${owner}/` }), name),
      el('span', { className: 'repo-item-meta', textContent: repoMeta(repo) })),
    badge
      ? el('span', { className: `badge badge-${badge.kind}`, textContent: badge.text })
      : el('span', { className: `dot ${repo.enabled ? 'on' : 'off'}`, title: repo.enabled ? 'Watching' : 'Paused' }));
  }));
}

function renderModels() {
  const models = [...new Set(state.repos.map((repo) => repo.model).filter(Boolean))];
  $('#models').replaceChildren(...models.map((model) => el('option', { value: model })));
}

/* ---------- Repository detail ---------- */

function card(iconName, title, description, aside, ...body) {
  return el('section', { className: 'card' },
    el('div', { className: 'card-head' },
      el('span', { className: 'card-icon' }, icon(iconName)),
      el('div', {}, el('h3', { textContent: title }), el('p', { className: 'card-desc', textContent: description })),
      aside),
    ...body);
}

function switchControl(on, labels, ariaLabel, onToggle) {
  return el('button', { type: 'button', role: 'switch', className: `switch${on ? ' on' : ''}`, 'aria-checked': String(on), 'aria-label': ariaLabel, onclick: () => onToggle(!on) },
    el('span', { className: 'switch-track' }, el('span', { className: 'switch-knob' })),
    el('span', { textContent: on ? labels[0] : labels[1] }));
}

function callout(kind, iconName, text) {
  return el('div', { className: `callout callout-${kind}` }, icon(iconName, 'sm'), el('p', { textContent: text }));
}

function detailHeader(repo) {
  const [owner, name] = repo.repo.split('/');
  return el('div', { className: 'detail-head' },
    avatar(owner, 'lg'),
    el('div', { className: 'detail-title' },
      el('div', { className: 'detail-owner', textContent: owner }),
      el('h2', { textContent: name }),
      el('a', { className: 'detail-link', href: `https://github.com/${repo.repo}`, target: '_blank', rel: 'noopener noreferrer' }, 'Open on GitHub', icon('external', 'sm'))),
    el('div', { className: 'detail-status' },
      switchControl(repo.enabled, ['Watching', 'Paused'], `Watch ${repo.repo}`, (on) => { repo.enabled = on; changed(); renderDetail(); }),
      el('span', { className: 'muted small', textContent: repo.enabled ? 'Checked for new commands every 2 minutes.' : 'Commands here are ignored until you turn it back on.' })));
}

function cleanLogin(value) {
  return value.trim().replace(/^@/, '').replace(/^https?:\/\/github\.com\//i, '').replace(/\/+$/, '');
}

function loginProblem(repo, login) {
  if (!LOGIN_RE.test(login)) return 'GitHub usernames use only letters, numbers and dashes.';
  if (repo.trusted_users.some((known) => key(known) === key(login))) return `${login} is already trusted here.`;
  return '';
}

function peopleSection(repo) {
  const people = repo.trusted_users.length
    ? el('div', { className: 'people' }, ...repo.trusted_users.map((login) => el('span', { className: 'person' },
      avatar(login, 'sm'),
      login,
      el('button', { type: 'button', className: 'icon-btn', title: `Remove ${login}`, 'aria-label': `Remove ${login}`, onclick: () => {
        repo.trusted_users = repo.trusted_users.filter((known) => known !== login);
        changed();
        renderDetail();
      } }, icon('x', 'sm')))))
    : el('p', { className: 'people people-empty', textContent: 'Nobody yet, so nobody can start a review in this repository.' });

  const input = el('input', { type: 'text', id: 'people-input', placeholder: 'GitHub username', autocomplete: 'off', spellcheck: false, 'aria-label': 'GitHub username to trust' });
  const add = el('button', { type: 'submit', className: 'btn', disabled: true }, icon('plus', 'sm'), 'Add');
  const hint = el('p', { className: 'field-hint', textContent: 'Press Enter to add. You can paste @username or a profile link.' });
  input.addEventListener('input', () => {
    const login = cleanLogin(input.value);
    const problem = login && loginProblem(repo, login);
    add.disabled = !login || Boolean(problem);
    input.classList.toggle('invalid', Boolean(problem));
    hint.classList.toggle('bad', Boolean(problem));
    hint.textContent = problem || 'Press Enter to add. You can paste @username or a profile link.';
  });
  const form = el('form', { className: 'inline-form', novalidate: '' }, input, add);
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const login = cleanLogin(input.value);
    if (!login || loginProblem(repo, login)) return;
    repo.trusted_users.push(login);
    changed();
    renderDetail();
    focusId('people-input');
  });

  const warning = callout('warn', 'alert', 'People listed here can start reviews by commenting the review command; everyone else is ignored. When tests are on, their own pull requests also run the test command on your Mac, so only add people whose code you would run yourself.');

  return card('users', 'Who can start reviews', 'People whose review commands the bot obeys in this repository only.', null, people, form, hint, warning);
}

function choice(title, description, checked, onPick) {
  return el('button', { type: 'button', role: 'radio', className: 'choice', 'aria-checked': String(checked), onclick: onPick },
    el('span', { className: 'radio' }),
    el('span', {}, el('span', { className: 'choice-title', textContent: title }), el('span', { className: 'choice-desc', textContent: description })));
}

function modelSection(repo) {
  const custom = repo.model !== '' || customModel.has(repo);
  const pick = (wantCustom) => {
    if (wantCustom) {
      customModel.add(repo);
    } else {
      customModel.delete(repo);
      repo.model = '';
      changed();
    }
    renderDetail();
    if (wantCustom) focusId('model-input');
  };
  const choices = el('div', { className: 'choices', role: 'radiogroup', 'aria-label': 'Review model' },
    choice('Codex default', 'Uses the model your Codex CLI is set up with.', !custom, () => pick(false)),
    choice('A specific model', 'Choose a model for this repository only.', custom, () => pick(true)));
  if (!custom) return card('spark', 'Review model', 'Which model reads the code and writes the review.', null, choices);

  const input = el('input', { type: 'text', id: 'model-input', className: 'mono', value: repo.model, placeholder: 'Model name', list: 'models', autocomplete: 'off', spellcheck: false, 'aria-label': 'Model name' });
  const hint = el('p', { className: 'field-hint', textContent: 'Use the same name you would pass to codex with -m. Empty means the Codex default.' });
  input.addEventListener('input', () => {
    const bad = !MODEL_RE.test(input.value);
    input.classList.toggle('invalid', bad);
    hint.classList.toggle('bad', bad);
    hint.textContent = bad ? 'Use letters, numbers, dots, dashes, colons or underscores (up to 64).' : 'Use the same name you would pass to codex with -m. Empty means the Codex default.';
    repo.model = input.value.trim();
    changed();
  });
  return card('spark', 'Review model', 'Which model reads the code and writes the review.', null, choices, el('div', { className: 'choice-extra' }, input, hint));
}

function testsSection(repo) {
  const on = repo.test_cmd !== '' || testsDraft.has(repo);
  const toggle = switchControl(on, ['On', 'Off'], `Run tests for ${repo.repo}`, (enable) => {
    if (enable) {
      testsDraft.add(repo);
      repo.test_cmd = parkedCommands.get(repo) || '';
    } else {
      testsDraft.delete(repo);
      parkedCommands.set(repo, repo.test_cmd);
      repo.test_cmd = '';
    }
    changed();
    renderDetail();
    if (enable) focusId('test-input');
  });
  if (!on) return card('flask', 'Run tests before reviewing', 'The reviewer gets the result and comments on test coverage.', toggle);

  const input = el('input', { type: 'text', id: 'test-input', className: 'mono', value: repo.test_cmd, placeholder: 'npm ci && npm test', autocomplete: 'off', spellcheck: false, 'aria-label': 'Test command' });
  input.addEventListener('input', () => {
    repo.test_cmd = input.value;
    changed();
  });
  return card('flask', 'Run tests before reviewing', 'The reviewer gets the result and comments on test coverage.', toggle,
    input,
    el('p', { className: 'field-hint', textContent: 'Runs in a throwaway copy of the pull request, with a time limit, only when its author is trusted here. The exit code and the end of the output go to the reviewer.' }));
}

function dangerSection(repo) {
  return el('div', { className: 'danger-row' },
    el('div', {}, el('h3', { textContent: 'Remove this repository' }), el('p', { className: 'muted small', textContent: 'The bot stops watching it. Reviews already posted stay on GitHub.' })),
    el('button', { type: 'button', className: 'btn danger', onclick: () => removeRepo(repo) }, icon('trash', 'sm'), 'Remove'));
}

function welcome() {
  return el('section', { className: 'card welcome' },
    el('span', { className: 'welcome-mark' }, icon('logo', 'lg')),
    el('h2', { textContent: 'Watch your first repository' }),
    el('p', { textContent: 'The bot checks your repositories every two minutes and reviews a pull request when someone you trust asks for it.' }),
    el('ol', { className: 'steps' },
      el('li', {}, el('strong', { textContent: 'Add a repository' }), 'Type owner/name or paste its GitHub link on the left.'),
      el('li', {}, el('strong', { textContent: 'Choose who you trust' }), 'Only their comments can start a review.'),
      el('li', {}, el('strong', { textContent: 'Ask for a review' }), 'Comment the review command on a pull request. The review appears there in a few minutes.')));
}

function renderDetail() {
  const detail = $('#detail');
  if (!state.loaded) {
    detail.replaceChildren(el('div', { className: 'card skeleton' }), el('div', { className: 'card skeleton tall' }));
    return;
  }
  const repo = selectedRepo();
  detail.replaceChildren(...(repo
    ? [detailHeader(repo), peopleSection(repo), modelSection(repo), testsSection(repo), dangerSection(repo)]
    : [welcome()]));
}

/* ---------- Adding and removing ---------- */

function parseRepo(value) {
  const text = value.trim().replace(/^https?:\/\/(www\.)?github\.com\//i, '').replace(/\.git$/i, '').replace(/\/+$/, '');
  return /^https?:/i.test(value.trim()) ? text.split('/').slice(0, 2).join('/') : text;
}

function repoProblem(name) {
  if (!REPO_RE.test(name) || ['.', '..'].includes(name.split('/')[1])) return 'Use owner/name, like octocat/hello-world, or paste the GitHub link.';
  if (state.repos.some((repo) => key(repo.repo) === key(name))) return 'That repository is already in the list.';
  return '';
}

const ADD_HINT = 'Paste a link or type owner/name.';

function onAddInput() {
  const name = parseRepo($('#add-repo').value);
  const problem = name && repoProblem(name);
  $('#add-button').disabled = !name || Boolean(problem);
  $('#add-repo').classList.toggle('invalid', Boolean(problem));
  $('#add-hint').classList.toggle('bad', Boolean(problem));
  $('#add-hint').textContent = problem || (name && name !== $('#add-repo').value.trim() ? `Will add ${name}.` : ADD_HINT);
}

function addRepo(event) {
  event.preventDefault();
  const name = parseRepo($('#add-repo').value);
  if (!name || repoProblem(name)) return;
  state.repos.push({ repo: name, enabled: true, trusted_users: [], model: '', test_cmd: '' });
  $('#add-repo').value = '';
  onAddInput();
  select(name);
  changed();
  focusId('people-input');
}

function removeRepo(repo) {
  const index = state.repos.indexOf(repo);
  state.repos.splice(index, 1);
  const neighbour = state.repos[Math.min(index, state.repos.length - 1)];
  state.selected = neighbour ? key(neighbour.repo) : '';
  changed();
  renderDetail();
  toast(`Removed ${repo.repo}. Save to make it final.`, {
    label: 'Undo',
    run: () => {
      if (state.saving || state.repos.some((known) => key(known.repo) === key(repo.repo))) {
        toast(`Could not undo: ${repo.repo} is already back in the list or a save is running.`);
        return;
      }
      state.repos.splice(Math.min(index, state.repos.length), 0, repo);
      select(repo.repo);
      changed();
    },
  });
}

/* ---------- Saving ---------- */

function renderSavebar() {
  const { added, edited, removed } = changeSummary();
  const parts = [[added, 'added'], [edited, 'edited'], [removed, 'removed']].filter(([count]) => count).map(([count, word]) => `${count} ${word}`);
  const dirty = parts.length > 0;
  $('#savebar').hidden = !dirty;
  $('#savebar-text').textContent = `Unsaved changes: ${parts.join(', ')}`;
  $('#save').disabled = !dirty || state.saving || !state.loaded;
  $('#discard').disabled = !dirty || state.saving;
  $('#errors').replaceChildren(...state.errors.map((message) => el('li', { textContent: message })));
  $('#errors').hidden = state.errors.length === 0;
}

// "repos[3].repo is not valid" reads better as "bad name: repo is not valid".
function describeError(message) {
  return message.replace(/^repos\[(\d+)\]\.?/, (_, index) => `${state.repos[index]?.repo || `Entry ${Number(index) + 1}`}: `);
}

function renderAll() {
  renderStats();
  renderList();
  renderDetail();
  renderSavebar();
  renderModels();
}

async function save() {
  if ($('#save').disabled) return;
  state.saving = true;
  $('#toast').hidden = true;
  $('#save').classList.add('busy');
  setEditable(false);
  try {
    const repos = (await api('/api/repos', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ repos: state.repos }) })).repos;
    state.repos = repos;
    state.savedRepos = clone(repos);
    state.errors = [];
    state.errorRepos = new Set();
    toast('Saved. The bot uses these settings from its next check, within 2 minutes.');
  } catch (error) {
    const indexes = (error.errors || []).map((message) => /^repos\[(\d+)\]/.exec(message)).filter(Boolean).map((match) => Number(match[1]));
    state.errorRepos = new Set(indexes.map((index) => key(state.repos[index]?.repo || '')));
    state.errors = error.errors?.length ? error.errors.map(describeError) : [`Could not save: ${error.message}`];
  } finally {
    state.saving = false;
    $('#save').classList.remove('busy');
    setEditable(true);
    renderAll();
  }
}

function discard() {
  state.repos = clone(state.savedRepos);
  state.errors = [];
  state.errorRepos = new Set();
  renderAll();
  toast('Changes discarded.');
}

async function loadRepos() {
  setEditable(false);
  $('#load-error').hidden = true;
  try {
    const repos = (await api('/api/repos')).repos;
    state.repos = repos;
    state.savedRepos = clone(repos);
    state.loaded = true;
    renderAll();
    setEditable(true);
  } catch (error) {
    $('#load-error-text').textContent = `Could not load your settings (${error.message}). Editing stays off so nothing gets overwritten.`;
    $('#load-error').hidden = false;
  }
}

/* ---------- Activity ---------- */

function logKind(message) {
  if (/fail|error|invalid|missing|timed out/i.test(message)) return 'bad';
  if (/^(Reviewed|Learned)\b/.test(message)) return 'good';
  if (/^Dispatch\b/.test(message)) return 'info';
  return '';
}

function logTime(stamp) {
  const date = new Date(stamp);
  if (Number.isNaN(date.getTime())) return { text: '', title: '' };
  const time = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  const today = date.toDateString() === new Date().toDateString();
  return { text: today ? time : `${date.toLocaleDateString([], { month: 'short', day: 'numeric' })} ${time}`, title: date.toLocaleString() };
}

function renderLog() {
  const filter = $('#log-filter').value.trim().toLowerCase();
  const problemsOnly = $('#log-problems').checked;
  const box = $('#log');
  const atEnd = box.scrollTop + box.clientHeight >= box.scrollHeight - 12;
  const lines = state.activity.log
    .map((line) => {
      const match = /^(\S+)\s+(.*)$/.exec(line);
      return match ? { stamp: match[1], text: match[2] } : { stamp: '', text: line };
    })
    .filter((line) => (!filter || line.text.toLowerCase().includes(filter)) && (!problemsOnly || logKind(line.text) === 'bad'));
  box.replaceChildren(...(lines.length
    ? lines.map((line) => {
      const time = logTime(line.stamp);
      return el('div', { className: `log-line ${logKind(line.text)}` },
        el('time', { className: 'log-time', dateTime: line.stamp, title: time.title, textContent: time.text }),
        el('span', { className: 'log-msg', textContent: line.text }));
    })
    : [el('p', { className: 'console-empty', textContent: state.activity.log.length ? 'No lines match.' : 'Nothing logged yet.' })]));
  if (atEnd) box.scrollTop = box.scrollHeight;
}

function renderReviews() {
  const list = $('#reviews');
  const reviews = state.activity.reviews.slice(0, 25);
  if (state.activityError) {
    list.replaceChildren(el('li', { className: 'timeline-empty bad' }, icon('alert'), state.activityError));
  } else if (!reviews.length) {
    list.replaceChildren(el('li', { className: 'timeline-empty' }, icon('clock', 'lg'), 'No reviews yet. When someone you trust comments the review command on a pull request, it shows up here.'));
  } else {
    list.replaceChildren(...reviews.map((review) => {
      const [owner] = String(review.repo).split('/');
      const title = [`${review.repo} `, el('span', { className: 'pr-number', textContent: `#${review.pr}` })];
      return el('li', { className: 'timeline-item' },
        avatar(owner, 'sm'),
        el('div', { className: 'timeline-body' },
          REPO_RE.test(review.repo)
            ? el('a', { className: 'timeline-title', href: `https://github.com/${review.repo}/pull/${Number(review.pr)}`, target: '_blank', rel: 'noopener noreferrer' }, ...title)
            : el('span', { className: 'timeline-title' }, ...title),
          el('div', { className: 'timeline-meta' },
            el('code', { className: 'sha', textContent: String(review.sha).slice(0, 7) }),
            el('time', { dateTime: review.at, title: new Date(review.at).toLocaleString(), textContent: ago(review.at) }))));
    }));
  }
  $('#updated').textContent = state.activityAt ? `Updated ${ago(state.activityAt)}` : '';
}

async function refreshActivity() {
  $('#refresh').classList.add('spinning');
  try {
    state.activity = await api('/api/activity');
    state.activityAt = Date.now();
    state.activityError = '';
  } catch (error) {
    state.activityError = `Could not load activity: ${error.message}`;
  } finally {
    $('#refresh').classList.remove('spinning');
    renderReviews();
    renderLog();
    renderStats();
  }
}

/* ---------- Tabs and start ---------- */

function showTab() {
  const active = location.hash === '#activity' ? 'activity' : 'repos';
  for (const tab of document.querySelectorAll('.tab')) {
    const on = tab.dataset.tab === active;
    tab.classList.toggle('active', on);
    tab.setAttribute('aria-selected', String(on));
  }
  $('#view-repos').hidden = active !== 'repos';
  $('#view-activity').hidden = active !== 'activity';
}

function start() {
  $('#brand-mark').append(icon('logo'));
  $('#local-pill').prepend(icon('lock', 'sm'));
  $('#refresh').prepend(icon('refresh', 'sm'));
  $('#add-button').append(icon('plus'));
  for (const tab of document.querySelectorAll('.tab')) {
    tab.addEventListener('click', () => { location.hash = tab.dataset.tab === 'activity' ? 'activity' : 'repositories'; });
  }
  window.addEventListener('hashchange', showTab);
  $('#add-repo').addEventListener('input', onAddInput);
  $('#add-form').addEventListener('submit', addRepo);
  $('#save').addEventListener('click', save);
  $('#discard').addEventListener('click', discard);
  $('#retry').addEventListener('click', loadRepos);
  $('#refresh').addEventListener('click', refreshActivity);
  $('#log-filter').addEventListener('input', renderLog);
  $('#log-problems').addEventListener('change', renderLog);
  document.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
      event.preventDefault();
      save();
    }
  });
  window.addEventListener('beforeunload', (event) => {
    const { added, edited, removed } = changeSummary();
    if (added + edited + removed) event.preventDefault();
  });
  showTab();
  renderAll();
  loadRepos();
  refreshActivity();
  setInterval(refreshActivity, REFRESH_MS);
}

start();
