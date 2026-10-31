# Builder instructions

## Read before building

Read the [design spec](docs/superpowers/specs/2026-10-31-pr-reviewer-design.md),
then the [implementation plan](docs/superpowers/plans/2026-10-31-pr-reviewer.md)
and the task you are working on. The spec is the source of truth; if the plan
or a task conflicts with it, stop and ask.

## How to work

Every change follows the `ub-mode` skill (`.claude/skills/ub-mode/SKILL.md`):
First Make it Work, Then Make it Right, Follow Practice. Load it before you
touch code.

## Project rules

- Bash 3.2 (the macOS `/bin/bash`): no associative arrays, no `mapfile`, no
  `${var,,}`. Entrypoints start with `#!/bin/bash` and `set -euo pipefail`.
- Runtime dependencies are `gh`, `jq`, `git`, `codex` and `perl` only. No
  Node or Python.
- Declare functions as `name() {` at column 0 and close them with `}` at
  column 0. The quality tools find functions by that shape.
- Code comments, commit messages and everything the bot posts on GitHub are
  in English.
- Prompts and scripts are written from scratch. Never copy text or code from
  another reviewer project, and never name one in files or commits.

## Tests

- Run `bash tests/run.sh [filter]`. The filter matches a test function name
  or a test file name.
- Tests never reach real GitHub or Codex: put fakes from `tests/fakes/` first
  on `PATH`.

## Quality gate

Run before every commit that changes code. Delegate to the `quality-gate`
agent to keep the main context small.

| Tool | Command | Passes when |
|---|---|---|
| crapper | `tools/crapper` | every function has CRAP below 10 |
| dryer | `tools/dryer` | no duplicated region ranks 0.8 or above |
| mutator | `tools/mutator --since HEAD` (full run: no `--since`) | no surviving mutants |

All three take `--help`. They analyze the project's Bash and jq code
outside `tests/` and `tools/`.

## Commits

Conventional Commits in English: `type(scope): summary` with types `feat`,
`fix`, `refactor`, `test`, `docs`, `chore`. The body says why, what changed
and how it was verified. Small, ordered commits on `main`. There is no
remote yet; push only once one exists.
