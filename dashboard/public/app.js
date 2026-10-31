'use strict';
// Rules mirror dashboard/validate.js for instant feedback; the server still decides.
const REPO_RE = /^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/;
const LOGIN_RE = /^[A-Za-z0-9-]{1,39}$/;
const MODEL_RE = /^[A-Za-z0-9._:-]{0,64}$/;
const REFRESH_MS = 30000;
const WEEK_MS = 7 * 24 * 3600 * 1000;
const CUSTOM = '__custom';

const state = {
  repos: [],
  savedRepos: [],
  selected: '',
  search: '',
  loaded: false,
  saving: false,
  errors: [],
  errorRepos: new Set(),
  engines: null,
  enginesError: '',
  activity: { reviews: [], log: [] },
  activityAt: 0,
  activityError: '',
  activityRepo: '',
};
// Screen-only choices that are not saved: "Other model" picked before typing
// a name, a tests switch turned on before typing a command, a command parked
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
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  external: '<path d="M7 17 17 7M8 7h9v9"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>',
  alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  terminal: '<path d="m5 8 4 4-4 4M12 16h7"/>',
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-6.4A8 8 0 1 1 21 12z"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
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
  // Only fixed strings from ICONS are ever parsed as markup.
  span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;
  return span;
}

function tone(name) {
  let hash = 0;
  for (const char of key(name)) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return (hash % 6) + 1;
}

const avatar = (name, size = '') => el('span', { className: `avatar av-${tone(name)} ${size}`, textContent: (String(name)[0] || '?').toUpperCase(), 'aria-hidden': 'true' });
const chip = (kind, text, iconName) => el('span', { className: `chip chip-${kind}` }, iconName && icon(iconName, 'sm'), text);

const relative = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
const UNITS = [[60, 'second', 1], [3600, 'minute', 60], [86400, 'hour', 3600], [604800, 'day', 86400], [2629800, 'week', 604800], [Infinity, 'month', 2629800]];

function ago(when) {
  const seconds = (new Date(when).getTime() - Date.now()) / 1000;
  if (!Number.isFinite(seconds)) return '';
  if (Math.abs(seconds) < 30) return 'just now';
  const [, unit, size] = UNITS.find(([limit]) => Math.abs(seconds) < limit);
  return relative.format(Math.round(seconds / size), unit);
}

const shortDate = (when) => new Date(when).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(body.error || res.statusText), { errors: body.errors || [] });
  return body;
}

let toastTimer;
function toast(message, action) {
  const box = $('#toast');
  const parts = [icon(action ? 'undo' : 'check'), el('span', { textContent: message })];
  if (action) parts.push(el('button', { type: 'button', className: 'btn quiet sm', onclick: () => { box.hidden = true; action.run(); } }, action.label));
  box.replaceChildren(...parts);
  box.hidden = false;
  box.classList.remove('show');
  void box.offsetWidth;
  box.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, action ? 8000 : 4000);
}

/* ---------- Engines ---------- */

const engineOf = (id) => (state.engines || []).find((engine) => engine.id === id);
const engineName = (id) => engineOf(id)?.name || (id === 'claude' ? 'Claude Code' : id === 'codex' ? 'Codex' : id);

function effortsFor(engine, modelId) {
  if (!engine) return [];
  const model = engine.models.find((candidate) => candidate.id === (modelId || engine.defaultModel));
  return model ? model.efforts : [...new Set(engine.models.flatMap((candidate) => candidate.efforts))];
}

function defaultEffortFor(engine, modelId) {
  if (!engine) return '';
  if (!modelId && engine.defaultEffort) return engine.defaultEffort;
  return engine.models.find((candidate) => candidate.id === (modelId || engine.defaultModel))?.defaultEffort || '';
}

function engineSummary(repo) {
  const engine = engineOf(repo.engine);
  const model = repo.model || (engine?.defaultModel ? engine.defaultModel : 'default model');
  return [engineName(repo.engine), model, repo.effort].filter(Boolean).join(' · ');
}

function commandPreview(repo) {
  const model = repo.model;
  const effort = repo.effort;
  if (repo.engine === 'claude') {
    return ['claude -p --restricted --tools Read,Grep,Glob', model && `--model ${model}`, effort && `--effort ${effort}`].filter(Boolean).join(' ');
  }
  return ['codex exec --sandbox read-only', model && `-m ${model}`, effort && `-c model_reasoning_effort=${effort}`].filter(Boolean).join(' ');
}

async function loadEngines() {
  try {
    state.engines = (await api('/api/engines')).engines;
    state.enginesError = '';
  } catch (error) {
    state.engines = [];
    state.enginesError = error.message;
  }
  if (state.loaded) renderDetail();
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

function unsavedState(repo, saved) {
  if (state.errorRepos.has(key(repo.repo))) return 'error';
  const before = saved.get(key(repo.repo));
  return before === undefined || before !== JSON.stringify(repo) ? 'unsaved' : '';
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
    renderList();
    renderDetail();
  }
  if (matchMedia('(max-width: 980px)').matches) $('.detail').scrollIntoView({ behavior: 'smooth' });
}

// Something in a repository changed: refresh everything except the open form,
// so the field being typed in keeps its focus.
function changed() {
  renderList();
  renderSavebar();
  renderHeroChips();
}

function setEditable(on) {
  for (const group of document.querySelectorAll('.lockable')) group.disabled = !on;
  renderSavebar();
}

function focusId(id) {
  const target = document.getElementById(id);
  if (target) target.focus();
}

/* ---------- Repository list ---------- */

function renderList() {
  const list = $('#repo-list');
  $('#repo-count').textContent = state.loaded ? String(state.repos.length) : '';
  if (!state.loaded) {
    list.replaceChildren(...[1, 2, 3].map(() => el('div', { className: 'skeleton row' })));
    return;
  }
  const shown = state.repos.filter((repo) => key(repo.repo).includes(key(state.search)));
  if (!shown.length) {
    list.replaceChildren(el('p', { className: 'empty-text', textContent: state.repos.length ? 'No repository matches.' : 'No repositories yet.' }));
    return;
  }
  const current = selectedRepo();
  const saved = savedMap();
  list.replaceChildren(...shown.map((repo) => {
    const [owner, name] = repo.repo.split('/');
    const mark = unsavedState(repo, saved);
    return el('button', {
      type: 'button',
      className: `row-item${repo === current ? ' selected' : ''}${repo.enabled ? '' : ' paused'}`,
      'aria-current': String(repo === current),
      title: repo.repo,
      onclick: () => select(repo.repo),
    },
    avatar(owner),
    el('span', { className: 'row-main' },
      el('span', { className: 'row-title', textContent: name }),
      el('span', { className: 'row-sub', textContent: `${owner} · ${engineName(repo.engine)}` })),
    mark && el('span', { className: `dot${mark === 'error' ? ' error' : ''}`, title: mark === 'error' ? 'Needs attention' : 'Unsaved changes' }),
    repo.enabled ? chip('mint', 'Watching') : chip('gray', 'Paused'));
  }));
}

/* ---------- Repository detail ---------- */

function card(title, subtitle, aside, ...body) {
  return el('section', { className: 'card' },
    el('div', { className: 'card-head' },
      el('div', {}, el('h2', { textContent: title }), subtitle && el('p', { className: 'card-sub', textContent: subtitle })),
      aside),
    ...body);
}

function switchControl(on, labels, ariaLabel, onToggle) {
  return el('button', { type: 'button', role: 'switch', className: `switch${on ? ' on' : ''}`, 'aria-checked': String(on), 'aria-label': ariaLabel, onclick: () => onToggle(!on) },
    el('span', { className: 'switch-track' }, el('span', { className: 'switch-knob' })),
    el('span', { textContent: on ? labels[0] : labels[1] }));
}

const note = (kind, iconName, text) => el('div', { className: `note note-${kind}` }, icon(iconName), el('p', { textContent: text }));

function heroChips(repo) {
  const people = repo.trusted_users.length;
  return [
    chip('purple', engineSummary(repo), 'terminal'),
    chip(people ? 'blue' : 'orange', people ? `${people} trusted` : 'Nobody trusted', 'users'),
    repo.test_cmd ? chip('mint', 'Tests on', 'check') : chip('gray', 'No tests'),
  ];
}

function renderHeroChips() {
  const holder = $('#hero-chips');
  const repo = selectedRepo();
  if (holder && repo) holder.replaceChildren(...heroChips(repo));
}

function heroCard(repo) {
  const [owner, name] = repo.repo.split('/');
  return el('section', { className: 'card' },
    el('div', { className: 'hero' },
      avatar(owner, 'lg'),
      el('div', { className: 'hero-main' },
        el('p', { className: 'hero-owner', textContent: owner }),
        el('h1', { textContent: name }),
        el('div', { className: 'chips', id: 'hero-chips' }, ...heroChips(repo))),
      el('div', { className: 'hero-side' },
        switchControl(repo.enabled, ['Watching', 'Paused'], `Watch ${repo.repo}`, (on) => { repo.enabled = on; changed(); renderDetail(); }),
        el('a', { className: 'gh-link', href: `https://github.com/${repo.repo}`, target: '_blank', rel: 'noopener noreferrer' }, 'Open on GitHub', icon('external', 'sm')))));
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

function peopleCard(repo) {
  const people = repo.trusted_users.length
    ? el('div', { className: 'people' }, ...repo.trusted_users.map((login) => el('div', { className: 'person' },
      avatar(login, 'sm'),
      el('div', { className: 'person-main' }, el('span', { className: 'person-name', textContent: login }), el('span', { className: 'person-role', textContent: 'Can start reviews' })),
      el('button', { type: 'button', className: 'icon-btn remove', title: `Remove ${login}`, 'aria-label': `Remove ${login}`, onclick: () => {
        repo.trusted_users = repo.trusted_users.filter((known) => known !== login);
        changed();
        renderDetail();
      } }, icon('x', 'sm')))))
    : el('p', { className: 'empty-text', textContent: 'Nobody yet, so no one can start a review here.' });

  const input = el('input', { type: 'text', id: 'people-input', className: 'field', placeholder: 'GitHub username', autocomplete: 'off', spellcheck: false, 'aria-label': 'GitHub username to trust' });
  const add = el('button', { type: 'submit', className: 'btn green', disabled: true }, icon('plus', 'sm'), 'Add');
  const hint = el('p', { className: 'hint', textContent: PEOPLE_HINT });
  input.addEventListener('input', () => {
    const login = cleanLogin(input.value);
    const problem = login && loginProblem(repo, login);
    add.disabled = !login || Boolean(problem);
    input.classList.toggle('invalid', Boolean(problem));
    hint.classList.toggle('bad', Boolean(problem));
    hint.textContent = problem || PEOPLE_HINT;
  });
  const form = el('form', { className: 'add-line', novalidate: '' }, input, add);
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const login = cleanLogin(input.value);
    if (!login || loginProblem(repo, login)) return;
    repo.trusted_users.push(login);
    changed();
    renderDetail();
    focusId('people-input');
  });

  return card('Trusted people', 'Only their review commands are obeyed in this repository.', chip('mint', String(repo.trusted_users.length)),
    people, form, hint,
    note('warn', 'alert', 'When tests are on, pull requests opened by these people also run the test command on your Mac. Only add people whose code you would run yourself.'));
}

function setEngine(repo, id) {
  if (repo.engine === id) return;
  repo.engine = id;
  repo.model = '';
  repo.effort = '';
  customModel.delete(repo);
  changed();
  renderDetail();
}

function setModel(repo, modelId) {
  repo.model = modelId;
  if (repo.effort && !effortsFor(engineOf(repo.engine), repo.model).includes(repo.effort)) repo.effort = '';
  changed();
}

function effortPill(repo, value, label) {
  return el('button', {
    type: 'button',
    role: 'radio',
    className: 'pill-option',
    'aria-checked': String(repo.effort === value),
    onclick: () => { repo.effort = value; changed(); renderDetail(); },
  }, label);
}

function modelField(repo, engine) {
  const models = engine ? engine.models : [];
  const known = models.some((model) => model.id === repo.model);
  const custom = (repo.model !== '' && !known) || customModel.has(repo);
  const selectBox = el('select', { className: 'select', id: 'model-select', 'aria-label': 'Model' },
    el('option', { value: '', textContent: engine?.defaultModel ? `CLI default (${engine.defaultModel})` : 'CLI default' }),
    ...models.map((model) => el('option', { value: model.id, textContent: model.name === model.id ? model.id : `${model.name} (${model.id})` })),
    el('option', { value: CUSTOM, textContent: 'Other model…' }));
  selectBox.value = custom ? CUSTOM : repo.model;
  selectBox.addEventListener('change', () => {
    if (selectBox.value === CUSTOM) {
      customModel.add(repo);
      setModel(repo, '');
    } else {
      customModel.delete(repo);
      setModel(repo, selectBox.value);
    }
    renderDetail();
    if (selectBox.value === CUSTOM) focusId('model-input');
  });
  const parts = [el('label', { className: 'label', htmlFor: 'model-select', textContent: 'Model' }), el('span', { className: 'select-wrap' }, selectBox, el('span', { className: 'select-chevron' }, icon('chevron', 'sm')))];
  if (custom) {
    const input = el('input', { type: 'text', id: 'model-input', className: 'field mono custom-model', value: repo.model, placeholder: repo.engine === 'claude' ? 'Full model name' : 'Model name', autocomplete: 'off', spellcheck: false, 'aria-label': 'Model name' });
    const hint = el('p', { className: 'hint', textContent: 'Any model name the CLI accepts.' });
    input.addEventListener('input', () => {
      const bad = !MODEL_RE.test(input.value.trim());
      input.classList.toggle('invalid', bad);
      hint.classList.toggle('bad', bad);
      hint.textContent = bad ? 'Letters, numbers, dots, dashes, colons or underscores, up to 64.' : 'Any model name the CLI accepts.';
      repo.model = input.value.trim();
      changed();
      $('#runs-code').textContent = commandPreview(repo);
    });
    parts.push(input, hint);
  }
  return el('div', {}, ...parts);
}

function effortField(repo, engine) {
  const efforts = effortsFor(engine, repo.model);
  const fallback = defaultEffortFor(engine, repo.model);
  const values = repo.effort && !efforts.includes(repo.effort) ? [...efforts, repo.effort] : efforts;
  return el('div', {},
    el('span', { className: 'label', textContent: 'Effort' }),
    el('div', { className: 'pills', role: 'radiogroup', 'aria-label': 'Effort' },
      effortPill(repo, '', fallback ? `Default · ${fallback}` : 'Default'),
      ...values.map((effort) => effortPill(repo, effort, effort))),
    el('p', { className: 'hint', textContent: 'Higher effort reads more of the code and takes longer.' }));
}

function engineCard(repo) {
  if (!state.engines) return card('Review engine', 'Looking for the CLIs installed on this Mac…', null, el('div', { className: 'skeleton line' }));
  const engine = engineOf(repo.engine);
  // Only installed CLIs are offered; a configured one that is missing stays visible with a warning.
  const installed = state.engines.filter((candidate) => candidate.installed || candidate.id === repo.engine);
  const known = installed.length ? installed : [{ id: repo.engine, name: engineName(repo.engine), installed: true }];
  const tabs = el('div', { className: 'segmented wide', role: 'radiogroup', 'aria-label': 'Review CLI' },
    ...known.map((candidate) => el('button', {
      type: 'button',
      role: 'radio',
      className: 'seg',
      'aria-checked': String(candidate.id === repo.engine),
      disabled: !candidate.installed && candidate.id !== repo.engine,
      title: candidate.installed ? candidate.version : 'Not installed on this Mac',
      onclick: () => setEngine(repo, candidate.id),
    }, candidate.name, !candidate.installed && el('span', { className: 'seg-note', textContent: 'not installed' }))));

  const notes = [];
  if (state.enginesError) notes.push(note('bad', 'alert', `Could not detect the installed CLIs (${state.enginesError}).`));
  if (engine && !engine.installed) notes.push(note('bad', 'alert', `${engine.name} is not installed on this Mac, so reviews here will fail until you install it or pick another CLI.`));
  notes.push(repo.engine === 'claude'
    ? note('info', 'shield', 'Uses your Claude plan. It can only read the pull request\'s files: no shell, no edits, no network.')
    : note('info', 'shield', 'Runs in Codex\'s read-only sandbox, without network, plugins or MCP servers.'));

  return card('Review engine', 'Which CLI reviews pull requests here, with which model and effort.', engine?.version && chip('gray', engine.version),
    tabs,
    el('div', { className: 'engine-grid' }, modelField(repo, engine), effortField(repo, engine)),
    el('div', { className: 'runs' }, icon('terminal', 'sm'), el('code', { id: 'runs-code', textContent: commandPreview(repo) })),
    ...notes);
}

function testsCard(repo) {
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
  if (!on) return card('Tests', 'Run the test suite before reviewing; the reviewer comments on the result.', toggle);
  const input = el('input', { type: 'text', id: 'test-input', className: 'field mono', value: repo.test_cmd, placeholder: 'npm ci && npm test', autocomplete: 'off', spellcheck: false, 'aria-label': 'Test command' });
  input.addEventListener('input', () => {
    repo.test_cmd = input.value;
    changed();
  });
  return card('Tests', 'Run the test suite before reviewing; the reviewer comments on the result.', toggle,
    el('label', { className: 'label', htmlFor: 'test-input', textContent: 'Command' }),
    input,
    el('p', { className: 'hint', textContent: 'Runs in a throwaway copy of the pull request with a time limit, only when its author is trusted here.' }));
}

function activityCard(repo) {
  return card('Activity', 'Reviews and bot events for this repository.',
    el('button', { type: 'button', className: 'btn sm', onclick: () => { state.activityRepo = key(repo.repo); location.hash = 'activity'; } }, 'Open full activity'),
    el('div', { id: 'repo-activity' }));
}

function removeCard(repo) {
  return card('Remove repository', 'The bot stops watching it. Reviews already posted stay on GitHub.',
    el('button', { type: 'button', className: 'btn danger sm', onclick: () => removeRepo(repo) }, icon('trash', 'sm'), 'Remove'));
}

function emptyState() {
  return el('section', { className: 'card' },
    el('div', { className: 'empty' },
      el('span', { className: 'empty-mark' }, icon('logo', 'lg')),
      el('h1', { textContent: 'Watch your first repository' }),
      el('p', { textContent: 'The bot checks your repositories every two minutes and reviews a pull request when someone you trust asks for it.' }),
      el('button', { type: 'button', className: 'btn green', onclick: openAdd }, icon('plus', 'sm'), 'Add repository')));
}

function renderDetail() {
  const detail = $('#detail');
  if (!state.loaded) {
    detail.replaceChildren(el('div', { className: 'skeleton block' }), el('div', { className: 'skeleton tall' }));
    return;
  }
  const repo = selectedRepo();
  detail.replaceChildren(...(repo
    ? [heroCard(repo), engineCard(repo), peopleCard(repo), testsCard(repo), activityCard(repo), removeCard(repo)]
    : [emptyState()]));
  renderRepoActivity();
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
  state.repos.push({ repo: name, enabled: true, trusted_users: [], engine: 'codex', model: '', effort: '', test_cmd: '' });
  $('#add-dialog').close();
  state.search = '';
  $('#repo-search').value = '';
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
  renderList();
  renderDetail();
  renderSavebar();
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

// Entries saved before engines existed have no engine or effort yet.
const withDefaults = (repo) => ({ engine: 'codex', effort: '', ...repo });

async function loadRepos() {
  setEditable(false);
  $('#load-error').hidden = true;
  try {
    const repos = (await api('/api/repos')).repos.map(withDefaults);
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
  if (/fail|error|invalid|missing|timed out|unknown/i.test(message)) return 'bad';
  if (/^(Reviewed|Learned)\b/.test(message)) return 'good';
  if (/^Dispatch\b/.test(message)) return 'info';
  return '';
}

function parsedLog() {
  return state.activity.log.map((line) => {
    const match = /^(\S+)\s+(.*)$/.exec(line);
    return match ? { stamp: match[1], text: match[2] } : { stamp: '', text: line };
  });
}

// Log lines name the repository as owner/name, often followed by #number.
const mentions = (line, repoKey) => !repoKey || new RegExp(`(^|[\\s"])${repoKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(#|:|"|\\s|$)`, 'i').test(line.text);

function logTime(stamp) {
  const date = new Date(stamp);
  if (Number.isNaN(date.getTime())) return { text: '', title: '' };
  const time = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  const today = date.toDateString() === new Date().toDateString();
  return { text: today ? time : `${date.toLocaleDateString([], { month: 'short', day: 'numeric' })} ${time}`, title: date.toLocaleString() };
}

function logLines(lines, emptyText) {
  if (!lines.length) return [el('p', { className: 'console-empty', textContent: emptyText })];
  return lines.map((line) => {
    const time = logTime(line.stamp);
    return el('div', { className: `log-line ${logKind(line.text)}` },
      el('time', { className: 'log-time', dateTime: line.stamp, title: time.title, textContent: time.text }),
      el('span', { className: 'log-msg', textContent: line.text }));
  });
}

const prLink = (review) => (REPO_RE.test(review.repo) ? `https://github.com/${review.repo}/pull/${Number(review.pr)}` : null);
const reviewsOf = (repoKey) => state.activity.reviews.filter((review) => !repoKey || key(review.repo) === repoKey);

function renderRepoActivity() {
  const holder = $('#repo-activity');
  const repo = selectedRepo();
  if (!holder || !repo) return;
  const repoKey = key(repo.repo);
  const reviews = reviewsOf(repoKey).slice(0, 5);
  const list = reviews.length
    ? el('div', { className: 'mini-list' }, ...reviews.map((review) => el(prLink(review) ? 'a' : 'div', { className: 'mini-item', href: prLink(review) || undefined, target: '_blank', rel: 'noopener noreferrer' },
      avatar(`#${review.pr}`, 'sm'),
      el('span', { className: 'mini-main' }, el('span', { className: 'mini-title', textContent: `Pull request #${review.pr}` }), el('span', { className: 'mini-sub', textContent: ago(review.at) })),
      el('code', { className: 'sha', textContent: String(review.sha).slice(0, 7) }))))
    : el('p', { className: 'empty-text', textContent: 'No reviews in this repository yet.' });
  const lines = parsedLog().filter((line) => mentions(line, repoKey)).slice(-12);
  const events = el('div', { className: 'console short' }, ...logLines(lines, 'Nothing logged for this repository yet.'));
  holder.replaceChildren(list, el('p', { className: 'subhead', textContent: 'Latest bot events' }), events);
  events.scrollTop = events.scrollHeight;
}

function stat(tint, iconName, value, label) {
  return el('div', { className: 'stat' },
    el('span', { className: `stat-icon chip-${tint}` }, icon(iconName, 'lg')),
    el('div', {}, el('div', { className: 'stat-value', textContent: value }), el('div', { className: 'stat-label', textContent: label })));
}

function renderActivityFilter() {
  const selectBox = $('#activity-repo');
  const names = [...new Set([...state.repos.map((repo) => repo.repo), ...state.activity.reviews.map((review) => review.repo)])].sort();
  selectBox.replaceChildren(el('option', { value: '', textContent: 'All repositories' }), ...names.map((name) => el('option', { value: key(name), textContent: name })));
  if (state.activityRepo && !names.some((name) => key(name) === state.activityRepo)) state.activityRepo = '';
  selectBox.value = state.activityRepo;
}

function renderActivityPage() {
  renderActivityFilter();
  const repoKey = state.activityRepo;
  const reviews = reviewsOf(repoKey);
  const recent = reviews.filter((review) => Date.now() - new Date(review.at).getTime() < WEEK_MS).length;
  const allLines = parsedLog().filter((line) => mentions(line, repoKey));
  const problems = allLines.filter((line) => logKind(line.text) === 'bad').length;
  const repos = repoKey ? state.repos.filter((repo) => key(repo.repo) === repoKey) : state.repos;
  const people = new Set(repos.flatMap((repo) => repo.trusted_users.map(key))).size;

  $('#activity-summary').textContent = reviews.length ? `Last review ${ago(reviews[0].at)}` : 'No reviews yet';
  $('#updated').textContent = state.activityAt ? `Updated ${ago(state.activityAt)}` : '';
  $('#stats').replaceChildren(
    stat('mint', 'chat', String(recent), 'Reviews this week'),
    stat('blue', 'eye', String(repos.filter((repo) => repo.enabled).length), 'Repositories watched'),
    stat('purple', 'users', String(people), 'Trusted people'),
    stat(problems ? 'pink' : 'yellow', 'alert', String(problems), 'Problems in the log'));

  if (state.activityError) {
    $('#reviews').replaceChildren(note('bad', 'alert', state.activityError));
  } else if (!reviews.length) {
    $('#reviews').replaceChildren(el('p', { className: 'empty-text', textContent: 'No reviews yet. When someone you trust comments the review command on a pull request, it shows up here.' }));
  } else {
    $('#reviews').replaceChildren(el('table', { className: 'table' },
      el('thead', {}, el('tr', {}, el('th', { textContent: 'Repository' }), el('th', { textContent: 'Pull request' }), el('th', { className: 'hide-sm', textContent: 'Commit' }), el('th', { textContent: 'Reviewed' }))),
      el('tbody', {}, ...reviews.slice(0, 30).map((review) => {
        const [owner] = String(review.repo).split('/');
        const link = prLink(review);
        return el('tr', {},
          el('td', {}, el('span', { className: 'repo-cell' }, avatar(owner, 'sm'), review.repo)),
          el('td', {}, link ? el('a', { href: link, target: '_blank', rel: 'noopener noreferrer' }, chip('mint', `#${review.pr}`)) : chip('gray', `#${review.pr}`)),
          el('td', { className: 'hide-sm' }, el('code', { className: 'sha', textContent: String(review.sha).slice(0, 7) })),
          el('td', { className: 'muted', title: new Date(review.at).toLocaleString(), textContent: `${ago(review.at)} · ${shortDate(review.at)}` }));
      }))));
  }
  renderLog(allLines);
}

function renderLog(lines = parsedLog().filter((line) => mentions(line, state.activityRepo))) {
  const filter = key($('#log-filter').value.trim());
  const problemsOnly = $('#log-problems').checked;
  const box = $('#log');
  const atEnd = box.scrollTop + box.clientHeight >= box.scrollHeight - 12;
  const shown = lines.filter((line) => (!filter || key(line.text).includes(filter)) && (!problemsOnly || logKind(line.text) === 'bad'));
  box.replaceChildren(...logLines(shown, state.activity.log.length ? 'No lines match.' : 'Nothing logged yet.'));
  if (atEnd) box.scrollTop = box.scrollHeight;
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
    renderActivityPage();
    renderRepoActivity();
  }
}

/* ---------- Views and start ---------- */

function showView() {
  const current = view();
  for (const button of document.querySelectorAll('.seg[data-view]')) button.classList.toggle('active', button.dataset.view === current);
  $('#page-repos').hidden = current !== 'repos';
  $('#page-activity').hidden = current !== 'activity';
  window.scrollTo(0, 0);
  if (current === 'activity') renderActivityPage();
  else renderAll();
}

function start() {
  $('#brand-mark').append(icon('logo'));
  $('#local-note').prepend(icon('lock', 'sm'));
  $('#nav-add').prepend(icon('plus', 'sm'));
  $('#search-icon').replaceWith(icon('search'));
  $('#activity-chevron').append(icon('chevron', 'sm'));
  $('#refresh').prepend(icon('refresh', 'sm'));
  $('#add-close').append(icon('x', 'sm'));
  for (const button of document.querySelectorAll('.seg[data-view]')) {
    button.addEventListener('click', () => { location.hash = button.dataset.view === 'activity' ? 'activity' : 'repositories'; });
  }
  $('#nav-add').addEventListener('click', openAdd);
  $('#repo-search').addEventListener('input', () => { state.search = $('#repo-search').value.trim(); renderList(); });
  $('#add-repo').addEventListener('input', onAddInput);
  $('#add-form').addEventListener('submit', addRepo);
  $('#add-cancel').addEventListener('click', () => $('#add-dialog').close());
  $('#add-close').addEventListener('click', () => $('#add-dialog').close());
  $('#add-dialog').addEventListener('click', (event) => { if (event.target === $('#add-dialog')) $('#add-dialog').close(); });
  $('#save').addEventListener('click', save);
  $('#discard').addEventListener('click', discard);
  $('#retry').addEventListener('click', loadRepos);
  $('#refresh').addEventListener('click', refreshActivity);
  $('#activity-repo').addEventListener('change', () => { state.activityRepo = $('#activity-repo').value; renderActivityPage(); });
  $('#log-filter').addEventListener('input', () => renderLog());
  $('#log-problems').addEventListener('change', () => renderLog());
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
  loadRepos();
  loadEngines();
  refreshActivity();
  setInterval(refreshActivity, REFRESH_MS);
}

start();
