'use strict';
// Which review CLIs this Mac has, and the models and effort levels each
// accepts. Read on demand; nothing here is ever written.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const CLAUDE_EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];
const CLAUDE_MODELS = [['fable', 'Fable'], ['opus', 'Opus'], ['sonnet', 'Sonnet']];
// Codex "ultra" delegates to sub-agents, which the bot keeps disabled.
const CODEX_HIDDEN_EFFORTS = ['ultra'];

function findOnPath(name, pathEnv) {
  for (const dir of String(pathEnv || '').split(':').filter(Boolean)) {
    const candidate = path.join(dir, name);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      // keep looking
    }
  }
  return '';
}

function versionOf(binary) {
  try {
    return execFileSync(binary, ['--version'], { encoding: 'utf8', timeout: 4000, stdio: ['ignore', 'pipe', 'ignore'] }).trim().split('\n')[0];
  } catch {
    return '';
  }
}

function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

function codexModels(home) {
  let cache;
  try {
    cache = JSON.parse(readText(path.join(home, 'models_cache.json')));
  } catch {
    return [];
  }
  return (Array.isArray(cache?.models) ? cache.models : [])
    .filter((model) => model.visibility === 'list' && typeof model.slug === 'string')
    .sort((a, b) => (a.priority ?? 999) - (b.priority ?? 999))
    .map((model) => ({
      id: model.slug,
      name: model.display_name || model.slug,
      efforts: (model.supported_reasoning_levels || []).map((level) => level.effort).filter((effort) => typeof effort === 'string' && !CODEX_HIDDEN_EFFORTS.includes(effort)),
      defaultEffort: model.default_reasoning_level || '',
    }));
}

// Only the top-level keys of config.toml matter here, before the first table.
function codexDefaults(home) {
  const topLevel = readText(path.join(home, 'config.toml')).split(/^\s*\[/m)[0];
  const value = (name) => (new RegExp(`^${name}\\s*=\\s*"([^"]*)"`, 'm').exec(topLevel) || [])[1] || '';
  return { defaultModel: value('model'), defaultEffort: value('model_reasoning_effort') };
}

function engine(id, name, pathEnv) {
  const binary = findOnPath(id, pathEnv);
  return { id, name, installed: Boolean(binary), version: binary ? versionOf(binary) : '' };
}

function listEngines({ pathEnv = process.env.PATH, codexHome = process.env.CODEX_HOME || path.join(os.homedir(), '.codex') } = {}) {
  return [
    { ...engine('codex', 'Codex', pathEnv), models: codexModels(codexHome), ...codexDefaults(codexHome) },
    {
      ...engine('claude', 'Claude Code', pathEnv),
      models: CLAUDE_MODELS.map(([id, name]) => ({ id, name, efforts: CLAUDE_EFFORTS, defaultEffort: '' })),
      defaultModel: '',
      defaultEffort: '',
    },
  ];
}

module.exports = { listEngines };
