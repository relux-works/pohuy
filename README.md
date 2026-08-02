# pohuy

Relux Works fork of [smixs/pohuy](https://github.com/smixs/pohuy), distributed
under the original MIT license.

This fork keeps the useful part: an explicit Russian profane chat tone for
technical collaboration. It removes mandatory phrasebook/reference loading,
benchmark claims, and broad frustration-based activation. The original
phrasebook, scenes, ontology, and attribution notes remain available as optional
references without entering the runtime context automatically.

## Behavior

- Activation is explicit: `/pohuy`, `$pohuy`, `включи похуй-режим`, `отвечай
  матом`, or an equivalent direct request.
- Incidental profanity, quoted profanity, anger, and frustration do not activate
  the skill.
- `lite` is the default; `full` and `ultra` require explicit selection.
- `нормальный режим` or `хватит материться` disables it for the session.
- Code, commands, logs, commits, PR text, documentation, safety warnings, and
  destructive instructions remain precise and clean.
- The installed skill has no runtime references to preload.

## Install

```bash
./setup.sh
```

This optional managed path clones or reuses
[relux-agents-infra](https://github.com/relux-works/relux-agents-infra), verifies
an existing checkout by exact origin, and then follows the shared installation
convention:

- copies the runtime skill to `~/.agents/skills/pohuy/`
- links `~/.claude/skills/pohuy` to the installed copy
- links `~/.codex/skills/pohuy` to the installed copy
- links the Claude `/pohuy` command from `~/.claude/commands/pohuy.md`

The source checkout remains the authoring location. Re-run `./setup.sh` after
changes; do not edit the installed copy directly. Plugin installation or manual
copy remains available when the shared runtime is not wanted.

## Tools

| Tool | Purpose | Command | Output |
| --- | --- | --- | --- |
| `setup.sh` | Install the skill and Claude command using the shared runtime layout. | `./setup.sh` | `~/.agents/skills/pohuy/` plus Claude/Codex symlinks |
| `check-skill-contract.sh` | Validate activation, context budgets, eval schemas, task-local ignores, and setup shape. | `./scripts/check-skill-contract.sh` | Deterministic contract result on stdout |
| `test-skill-contract.sh` | Run negative schema/budget/origin tests and an isolated idempotent install. | `./scripts/test-skill-contract.sh` | Regression test result on stdout |
| `validate-skill.sh` | Validate skill frontmatter, naming, and structure from a relux-agents-infra checkout. | `/path/to/relux-agents-infra/.skills/skill-creator/scripts/validate-skill.sh skills/pohuy` | Validation result on stdout |
| `git diff --check` | Detect malformed patch whitespace before review. | `git diff --check` | No output when clean |

## Repository Layout

- `skills/pohuy/SKILL.md` — compact runtime instructions
- `skills/pohuy/references/` — optional upstream phrasebook, scenes, and ontology
- `commands/pohuy.md` — Claude slash command
- `evals/` — semantic, activation, and context-budget contracts
- `scripts/` — deterministic validation and regression tests
- `.claude-plugin/` — optional Claude plugin metadata
- `setup.sh` — agents-infra-style global installer
- `LICENSE` — original MIT license and attribution

## Upstream

The original project is retained as the `upstream` Git remote. Review upstream
changes before merging because this fork intentionally maintains narrower
activation and a smaller runtime context.
