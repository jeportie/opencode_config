# Claude Relay Mode

## Mission

Use Claude Code as the primary executor for any task. If Claude hits rate or usage limits, package all progress and context so OpenCode can continue immediately on its own models.

## Quick Start

Use the supervisor wrapper for end-to-end automation:

`./scripts/relay-supervisor.sh --task "<your task>"`

Useful flags:

- `--simulate-limit` to test fallback without spending Claude quota
- `--no-opencode` to stop after bundle creation
- `--claude-model` and `--opencode-model` to pin models

## Workflow

1. Clarify task goal and completion criteria.
2. Execute in small checkpoints and keep concise progress notes.
3. If a limit trigger appears (`429`, `rate_limit_exceeded`, `usage limit reached`), stop risky operations.
4. Generate handoff bundle:
   `./scripts/create-handoff-bundle.sh --task "<task>" --reason "<limit reason>"`
5. Complete `SUMMARY.md` and return `HANDOFF READY` output.
6. Launch OpenCode continuation with the generated bundle prompt.

## Handoff Output Contract

When handoff is triggered, return:

```markdown
## HANDOFF READY
- Bundle: <path>
- Trigger: <reason>
- Branch: <branch>@<short-sha>
- Completed: <1-3 bullets>
- Remaining: <1-3 bullets>
- First OpenCode action: <single step>
```

## Resume Contract

OpenCode resumes by reading, in order:

1. `context.json`
2. `SUMMARY.md`
3. `NEXT_STEPS.md`
4. `working.diff`
5. `staged.diff`
