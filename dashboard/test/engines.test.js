'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { listEngines } = require('../engines');

function fakeMachine({ codex = true, claude = true } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'engines-'));
  const bin = path.join(dir, 'bin');
  const home = path.join(dir, 'codex-home');
  fs.mkdirSync(bin);
  fs.mkdirSync(home);
  const tool = (name, version) => {
    fs.writeFileSync(path.join(bin, name), `#!/bin/sh\necho "${version}"\n`);
    fs.chmodSync(path.join(bin, name), 0o755);
  };
  if (codex) tool('codex', 'codex-cli 9.9.0');
  if (claude) tool('claude', '3.0.0 (Claude Code)');
  const level = (effort) => ({ effort, description: effort });
  fs.writeFileSync(path.join(home, 'models_cache.json'), JSON.stringify({ models: [
    { slug: 'beta-model', display_name: 'Beta', visibility: 'list', priority: 2, default_reasoning_level: 'low', supported_reasoning_levels: ['low', 'high'].map(level) },
    { slug: 'hidden-model', display_name: 'Hidden', visibility: 'hide', priority: 1, default_reasoning_level: 'low', supported_reasoning_levels: [level('low')] },
    { slug: 'alpha-model', display_name: 'Alpha', visibility: 'list', priority: 1, default_reasoning_level: 'medium', supported_reasoning_levels: ['low', 'medium', 'max', 'ultra'].map(level) },
  ] }));
  fs.writeFileSync(path.join(home, 'config.toml'), 'notify = ["x"]\nmodel = "alpha-model"\nmodel_reasoning_effort = "max"\n\n[profiles.other]\nmodel = "beta-model"\n');
  return { dir, pathEnv: `${bin}:/usr/bin:/bin`, codexHome: home };
}

test('lists installed engines with their versions', () => {
  const machine = fakeMachine();
  const [codex, claude] = listEngines(machine);
  assert.deepEqual([codex.id, codex.installed, codex.version], ['codex', true, 'codex-cli 9.9.0']);
  assert.deepEqual([claude.id, claude.installed, claude.version], ['claude', true, '3.0.0 (Claude Code)']);
  fs.rmSync(machine.dir, { recursive: true, force: true });
});

test('marks a missing CLI as not installed', () => {
  const machine = fakeMachine({ claude: false });
  const claude = listEngines(machine).find((engine) => engine.id === 'claude');
  assert.deepEqual([claude.installed, claude.version], [false, '']);
  fs.rmSync(machine.dir, { recursive: true, force: true });
});

test('reads Codex models in display order, without hidden models or ultra', () => {
  const machine = fakeMachine();
  const codex = listEngines(machine)[0];
  assert.deepEqual(codex.models, [
    { id: 'alpha-model', name: 'Alpha', efforts: ['low', 'medium', 'max'], defaultEffort: 'medium' },
    { id: 'beta-model', name: 'Beta', efforts: ['low', 'high'], defaultEffort: 'low' },
  ]);
  assert.deepEqual([codex.defaultModel, codex.defaultEffort], ['alpha-model', 'max']);
  fs.rmSync(machine.dir, { recursive: true, force: true });
});

test('a missing or broken Codex cache gives no models instead of failing', () => {
  const machine = fakeMachine();
  fs.writeFileSync(path.join(machine.codexHome, 'models_cache.json'), '{broken');
  fs.rmSync(path.join(machine.codexHome, 'config.toml'));
  const codex = listEngines(machine)[0];
  assert.deepEqual([codex.models, codex.defaultModel, codex.defaultEffort], [[], '', '']);
  fs.rmSync(machine.dir, { recursive: true, force: true });
});

test('offers Claude Code aliases and its effort levels', () => {
  const machine = fakeMachine();
  const claude = listEngines(machine)[1];
  assert.deepEqual(claude.models.map((model) => model.id), ['fable', 'opus', 'sonnet']);
  assert.deepEqual(claude.models[0].efforts, ['low', 'medium', 'high', 'xhigh', 'max']);
  fs.rmSync(machine.dir, { recursive: true, force: true });
});
