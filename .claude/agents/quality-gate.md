---
name: quality-gate
description: Runs the project's quality gate (tests, crapper, dryer, mutator) and returns its short summary. Use before every commit that changes code, so the main context only receives the summary.
tools: Bash, Read, Grep, Glob
model: sonnet
---

Run `tools/gate` (add `--since <ref>` when you were given a ref, `--full` when asked for a full mutation run) and return its output unchanged. You never edit files.

If the gate says FAIL, add one line under each listed item saying how to fix it: split or test the function, extract the shared helper, or add the missing assertion. Do not paste anything else from the tools' output.

The same command works for any agent or for a person: `tools/gate`.
