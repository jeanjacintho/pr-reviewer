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
const view = () => (location.hash === '#activity' ? 'activity' : 'repos');

const ICONS = {
  logo: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M6 8.5v7M18 15.5V11a4 4 0 0 0-4-4h-4"/><path d="m12 4.5-2.5 2.5L12 9.5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  pulse: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  external: '<path d="M7 17 17 7M8 7h9v9"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>',
  alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-1"/>',
};

// Larger line drawings for choices and empty states.
const ART = {
  defaults: '<path d="M7 15h22M37 15h4M7 33h6M21 33h20"/><circle cx="33" cy="15" r="4"/><circle cx="17" cy="33" r="4"/><path d="M7 24h12M27 24h14"/><circle cx="23" cy="24" r="4"/>',
  specific: '<path d="M7 40 15 26l10 6 13-20"/><circle cx="7" cy="40" r="2.5"/><circle cx="15" cy="26" r="2.5"/><circle cx="25" cy="32" r="2.5"/><path d="M31 11.5 38.5 10l1 7.5"/>',
  repo: '<circle cx="14" cy="11" r="4.5"/><circle cx="14" cy="37" r="4.5"/><circle cx="34" cy="37" r="4.5"/><path d="M14 15.5v17M34 32.5V22a7 7 0 0 0-7-7h-6"/><path d="m25 10.5-4.5 4.5 4.5 4.5"/>',
  chat: '<path d="M41 24a16 16 0 0 1-23.4 14.2L8 41l2.8-9.6A16 16 0 1 1 41 24z"/><path d="m18 24 5 5 8-9"/>',
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

// Only fixed strings from ICONS and ART are ever parsed as markup.
function drawing(className, viewBox, paths, strokeWidth) {
  const span = el('span', { className, 'aria-hidden': 'true' });
  span.innerHTML = `<svg viewBox="${viewBox}" fill="none" stroke="currentColor" stroke-width="${strokeWidth}" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
  return span;
}

const icon = (name, size = '') => drawing(`icon ${size}`, '0 0 24 24', ICONS[name], 1.8);
const art = (name, size = '') => drawing(`art ${size}`, '0 0 48 48', ART[name], 1.6);
const avatar = (name, size = '') => el('span', { className: `avatar ${size}`, textContent: (String(name)[0] || '?').toUpperCase(), 'aria-hidden': 'true' });

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
  const parts = [el('span', { textContent: message })];
  if (action) parts.push(el('button', { type: 'button', className: 'btn quiet', onclick: () => { box.hidden = true; action.run(); } }, icon('undo', 'sm'), action.label));
  box.replaceChildren(...parts);
  box.hidden = false;
  box.classList.remove('show');
  void box.offsetWidth;
  box.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, action ? 8000 : 4000);
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
  if (state.errorRepos.has(key(repo.repo))) return { kind: 'error', text: 'Needs attention' };
  const before = saved.get(key(repo.repo));
  if (before === undefined) return { kind: 'new', text: 'Not saved yet' };
  if (before !== JSON.stringify(repo)) return { kind: 'edited', text: 'Unsaved changes' };
  return null;
}

function selectedRepo() {
  const repo = state.repos.find((candidate) => key(candidate.repo) === state.selected) || state.repos[0];
  state.selected = repo ? key(repo.repo) : '';
  return repo;
}

function select(name) {
  state.selected = key(name);
  if (view() === 'activity') {
    location.hash = 'repositories';
  } else {
    renderNav();
    renderDetail();
  }
  if (matchMedia('(max-width: 860px)').matches) $('.content').scrollIntoView({ behavior: 'smooth' });
}

// Something in a repository changed: refresh everything except the open page,
// so the field being typed in keeps its focus.
function changed() {
  renderNav();
  renderSavebar();
  renderModels();
}

function setEditable(on) {
  for (const group of document.querySelectorAll('.lockable')) group.disabled = !on;
  renderSavebar();
}

function focusId(id) {
  const target = document.getElementById(id);
  if (target) target.focus();
}

/* ---------- Navigation ---------- */

function renderNav() {
  const list = $('#repo-list');
  const onActivity = view() === 'activity';
  $('#nav-activity').classList.toggle('active', onActivity);
  $('#repo-count').textContent = state.loaded && state.repos.length ? String(state.repos.length) : '';
  if (!state.loaded) {
    list.replaceChildren(...[1, 2, 3].map(() => el('div', { className: 'nav-item skeleton' })));
    return;
  }
  if (!state.repos.length) {
    list.replaceChildren(el('p', { className: 'nav-empty', textContent: 'None yet' }));
    return;
  }
  const current = selectedRepo();
  const saved = savedMap();
  list.replaceChildren(...state.repos.map((repo) => {
    const badge = repoBadge(repo, saved);
    const active = !onActivity && repo === current;
    return el('button', {
      type: 'button',
      className: `nav-item repo${active ? ' active' : ''}${repo.enabled ? '' : ' paused'}`,
      'aria-current': active ? 'page' : 'false',
      title: repo.enabled ? repo.repo : `${repo.repo} (paused)`,
      onclick: () => select(repo.repo),
    },
    el('span', { className: `status ${repo.enabled ? 'on' : 'off'}` }),
    el('span', { className: 'nav-text', textContent: repo.repo }),
    badge && el('span', { className: `mark mark-${badge.kind}`, title: badge.text, 'aria-label': badge.text }));
  }));
}

function renderModels() {
  const models = [...new Set(state.repos.map((repo) => repo.model).filter(Boolean))];
  $('#models').replaceChildren(...models.map((model) => el('option', { value: model })));
}

/* ---------- Repository page ---------- */

function row(title, description, ...body) {
  return el('section', { className: 'row' },
    el('div', { className: 'row-label' }, el('h2', { textContent: title }), el('p', { textContent: description })),
    el('div', { className: 'row-body' }, ...body));
}

function switchControl(on, labels, ariaLabel, onToggle) {
  return el('button', { type: 'button', role: 'switch', className: `switch${on ? ' on' : ''}`, 'aria-checked': String(on), 'aria-label': ariaLabel, onclick: () => onToggle(!on) },
    el('span', { className: 'switch-track' }, el('span', { className: 'switch-knob' })),
    el('span', { textContent: on ? labels[0] : labels[1] }));
}

function repoHead(repo) {
  const [owner, name] = repo.repo.split('/');
  return el('header', { className: 'page-head' },
    el('div', {},
      el('p', { className: 'eyebrow', textContent: owner }),
      el('h1', { textContent: name }),
      el('a', { className: 'subtle-link', href: `https://github.com/${repo.repo}`, target: '_blank', rel: 'noopener noreferrer' }, 'View on GitHub', icon('external', 'sm'))),
    el('div', { className: 'head-side' },
      switchControl(repo.enabled, ['Watching', 'Paused'], `Watch ${repo.repo}`, (on) => { repo.enabled = on; changed(); renderDetail(); }),
      el('p', { className: 'hint', textContent: repo.enabled ? 'Checked for commands every 2 minutes' : 'Commands here are ignored for now' })));
}

function cleanLogin(value) {
  return value.trim().replace(/^@/, '').replace(/^https?:\/\/github\.com\//i, '').replace(/\/+$/, '');
}

function loginProblem(repo, login) {
  if (!LOGIN_RE.test(login)) return 'GitHub usernames use only letters, numbers and dashes.';
  if (repo.trusted_users.some((known) => key(known) === key(login))) return `${login} is already on the list.`;
  return '';
}

const PEOPLE_HINT = 'Press Enter to add. @username or a profile link works too.';

function peopleRow(repo) {
  const people = repo.trusted_users.length
    ? el('div', { className: 'people' }, ...repo.trusted_users.map((login) => el('span', { className: 'person' },
      avatar(login),
      login,
      el('button', { type: 'button', className: 'icon-btn', title: `Remove ${login}`, 'aria-label': `Remove ${login}`, onclick: () => {
        repo.trusted_users = repo.trusted_users.filter((known) => known !== login);
        changed();
        renderDetail();
      } }, icon('x', 'sm')))))
    : el('p', { className: 'people-empty', textContent: 'Nobody yet, so no one can start a review here.' });

  const input = el('input', { type: 'text', id: 'people-input', placeholder: 'GitHub username', autocomplete: 'off', spellcheck: false, 'aria-label': 'GitHub username to trust' });
  const add = el('button', { type: 'submit', className: 'btn', disabled: true }, 'Add');
  const hint = el('p', { className: 'hint', textContent: PEOPLE_HINT });
  input.addEventListener('input', () => {
    const login = cleanLogin(input.value);
    const problem = login && loginProblem(repo, login);
    add.disabled = !login || Boolean(problem);
    input.classList.toggle('invalid', Boolean(problem));
    hint.classList.toggle('bad', Boolean(problem));
    hint.textContent = problem || PEOPLE_HINT;
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

  return row('Trusted people', 'Only their review commands are obeyed in this repository.',
    people, form, hint,
    el('div', { className: 'note' }, icon('alert'), el('p', { textContent: 'When tests are on, pull requests opened by these people also run the test command on your Mac. Only add people whose code you would run yourself.' })));
}

function choice(artName, title, description, checked, onPick) {
  return el('button', { type: 'button', role: 'radio', className: 'choice', 'aria-checked': String(checked), onclick: onPick },
    checked && el('span', { className: 'pill', textContent: 'In use' }),
    art(artName),
    el('span', { className: 'choice-title', textContent: title }),
    el('span', { className: 'choice-desc', textContent: description }));
}

const MODEL_HINT = 'The name you would pass to codex with -m.';

function modelRow(repo) {
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
    choice('defaults', 'Codex default', 'Uses the model your Codex CLI is already set up with.', !custom, () => pick(false)),
    choice('specific', 'Specific model', 'Pick a model for this repository only.', custom, () => pick(true)));
  if (!custom) return row('Review model', 'Which model reads the code and writes the review.', choices);

  const input = el('input', { type: 'text', id: 'model-input', className: 'mono', value: repo.model, placeholder: 'Model name', list: 'models', autocomplete: 'off', spellcheck: false });
  const hint = el('p', { className: 'hint', textContent: MODEL_HINT });
  input.addEventListener('input', () => {
    const bad = !MODEL_RE.test(input.value.trim());
    input.classList.toggle('invalid', bad);
    hint.classList.toggle('bad', bad);
    hint.textContent = bad ? 'Letters, numbers, dots, dashes, colons or underscores, up to 64.' : MODEL_HINT;
    repo.model = input.value.trim();
    changed();
  });
  return row('Review model', 'Which model reads the code and writes the review.', choices,
    el('div', { className: 'choice-extra' }, el('label', { className: 'field-label', htmlFor: 'model-input', textContent: 'Model name' }), input, hint));
}

function testsRow(repo) {
  const on = repo.test_cmd !== '' || testsDraft.has(repo);
  const toggle = switchControl(on, ['Run tests before each review', 'Tests are off'], `Run tests for ${repo.repo}`, (enable) => {
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
  const description = 'The reviewer sees the result and comments on test coverage.';
  if (!on) return row('Tests', description, toggle);

  const input = el('input', { type: 'text', id: 'test-input', className: 'mono', value: repo.test_cmd, placeholder: 'npm ci && npm test', autocomplete: 'off', spellcheck: false });
  input.addEventListener('input', () => {
    repo.test_cmd = input.value;
    changed();
  });
  return row('Tests', description,
    el('div', { className: 'stack' }, toggle,
      el('div', {},
        el('label', { className: 'field-label', htmlFor: 'test-input', textContent: 'Command' }),
        input,
        el('p', { className: 'hint', textContent: 'Runs in a throwaway copy of the pull request with a time limit, only when its author is trusted here.' }))));
}

function removeRow(repo) {
  return row('Remove', 'The bot stops watching this repository. Reviews already posted stay on GitHub.',
    el('button', { type: 'button', className: 'btn danger', onclick: () => removeRepo(repo) }, icon('trash', 'sm'), 'Remove repository'));
}

function emptyState() {
  return el('div', { className: 'empty' },
    art('repo', 'lg'),
    el('h1', { textContent: 'Watch your first repository' }),
    el('p', { textContent: 'The bot checks your repositories every two minutes and reviews a pull request when someone you trust asks for it.' }),
    el('button', { type: 'button', className: 'btn primary', onclick: openAdd }, icon('plus', 'sm'), 'Add repository'));
}

function renderDetail() {
  const detail = $('#detail');
  if (!state.loaded) {
    detail.replaceChildren(el('div', { className: 'skeleton block' }), el('div', { className: 'skeleton block tall' }));
    return;
  }
  const repo = selectedRepo();
  detail.replaceChildren(...(repo ? [repoHead(repo), peopleRow(repo), modelRow(repo), testsRow(repo), removeRow(repo)] : [emptyState()]));
}

/* ---------- Adding and removing ---------- */

function parseRepo(value) {
  const text = value.trim().replace(/^https?:\/\/(www\.)?github\.com\//i, '').replace(/\.git$/i, '').replace(/\/+$/, '');
  return /^https?:/i.test(value.trim()) ? text.split('/').slice(0, 2).join('/') : text;
}

function repoProblem(name) {
  if (!REPO_RE.test(name) || ['.', '..'].includes(name.split('/')[1])) return 'Use owner/name, like octocat/hello-world.';
  if (state.repos.some((repo) => key(repo.repo) === key(name))) return 'That repository is already in the list.';
  return '';
}

const ADD_HINT = 'For example octocat/hello-world';

function onAddInput() {
  const raw = $('#add-repo').value;
  const name = parseRepo(raw);
  const problem = name && repoProblem(name);
  $('#add-button').disabled = !name || Boolean(problem);
  $('#add-repo').classList.toggle('invalid', Boolean(problem));
  $('#add-hint').classList.toggle('bad', Boolean(problem));
  $('#add-hint').textContent = problem || (name && name !== raw.trim() ? `Will add ${name}` : ADD_HINT);
}

function openAdd() {
  $('#add-repo').value = '';
  onAddInput();
  $('#add-dialog').showModal();
  $('#add-repo').focus();
}

function addRepo(event) {
  event.preventDefault();
  const name = parseRepo($('#add-repo').value);
  if (state.saving || !name || repoProblem(name)) return;
  state.repos.push({ repo: name, enabled: true, trusted_users: [], model: '', test_cmd: '' });
  $('#add-dialog').close();
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
  toast(`Removed ${repo.repo}`, {
    label: 'Undo',
    run: () => {
      if (state.saving || state.repos.some((known) => key(known.repo) === key(repo.repo))) {
        toast(`Could not undo: ${repo.repo} is back in the list or a save is running.`);
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
  $('#savebar-text').textContent = `Unsaved changes · ${parts.join(', ')}`;
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
  renderNav();
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
    toast('Saved. The bot uses it from its next check.');
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
  toast('Changes discarded');
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
    list.replaceChildren(el('li', { className: 'list-empty bad' }, state.activityError));
  } else if (!reviews.length) {
    list.replaceChildren(el('li', { className: 'list-empty' }, art('chat'), 'No reviews yet. When someone you trust comments the review command on a pull request, it shows up here.'));
  } else {
    list.replaceChildren(...reviews.map((review) => {
      const [owner] = String(review.repo).split('/');
      const label = `${review.repo} #${review.pr}`;
      return el('li', { className: 'list-item' },
        avatar(owner, 'md'),
        el('div', { className: 'list-main' },
          REPO_RE.test(review.repo)
            ? el('a', { className: 'list-title', href: `https://github.com/${review.repo}/pull/${Number(review.pr)}`, target: '_blank', rel: 'noopener noreferrer', textContent: label })
            : el('span', { className: 'list-title', textContent: label }),
          el('span', { className: 'list-sub', textContent: ago(review.at) })),
        el('div', { className: 'list-meta' },
          el('code', { className: 'sha', textContent: String(review.sha).slice(0, 7) }),
          el('time', { dateTime: review.at, textContent: new Date(review.at).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) })));
    }));
  }
  const recent = state.activity.reviews.filter((review) => Date.now() - new Date(review.at).getTime() < WEEK_MS).length;
  $('#activity-summary').textContent = state.activity.reviews.length
    ? `${recent} ${recent === 1 ? 'review' : 'reviews'} this week · last one ${ago(state.activity.reviews[0].at)}`
    : 'Reviews and bot events from this Mac.';
  $('#updated').textContent = state.activityAt ? `Updated ${ago(state.activityAt)}` : '';
}

async function refreshActivity() {
  $('#refresh').disabled = true;
  try {
    state.activity = await api('/api/activity');
    state.activityAt = Date.now();
    state.activityError = '';
  } catch (error) {
    state.activityError = `Could not load activity: ${error.message}`;
  } finally {
    $('#refresh').disabled = false;
    renderReviews();
    renderLog();
  }
}

/* ---------- Views and start ---------- */

function showView() {
  const current = view();
  $('#page-repos').hidden = current !== 'repos';
  $('#page-activity').hidden = current !== 'activity';
  renderNav();
  if (current === 'repos') renderDetail();
}

function start() {
  $('#brand-mark').append(icon('logo'));
  $('#nav-add').prepend(icon('plus'));
  $('#nav-activity').prepend(icon('pulse'));
  $('#nav-footer').prepend(icon('lock', 'sm'));
  $('#refresh').prepend(icon('refresh', 'sm'));
  $('#add-close').append(icon('x'));
  $('#nav-add').addEventListener('click', openAdd);
  $('#nav-activity').addEventListener('click', () => { location.hash = 'activity'; });
  $('#add-repo').addEventListener('input', onAddInput);
  $('#add-form').addEventListener('submit', addRepo);
  $('#add-cancel').addEventListener('click', () => $('#add-dialog').close());
  $('#add-close').addEventListener('click', () => $('#add-dialog').close());
  $('#add-dialog').addEventListener('click', (event) => { if (event.target === $('#add-dialog')) $('#add-dialog').close(); });
  $('#save').addEventListener('click', save);
  $('#discard').addEventListener('click', discard);
  $('#retry').addEventListener('click', loadRepos);
  $('#refresh').addEventListener('click', refreshActivity);
  $('#log-filter').addEventListener('input', renderLog);
  $('#log-problems').addEventListener('change', renderLog);
  window.addEventListener('hashchange', showView);
  document.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
      event.preventDefault();
      if (!$('#add-dialog').open) save();
    }
  });
  window.addEventListener('beforeunload', (event) => {
    const { added, edited, removed } = changeSummary();
    if (added + edited + removed) event.preventDefault();
  });
  showView();
  renderAll();
  loadRepos();
  refreshActivity();
  setInterval(refreshActivity, REFRESH_MS);
}

start();
