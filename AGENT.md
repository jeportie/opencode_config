# Global Rules

No default agent active. Available modes:

- `/pedagogy` — Pedagogical Engineering Agent (teaching-focused development)
- `/pair-programmer` — Pair Programmer Agent (TDD)

## Git Commits

- NEVER add `Co-Authored-By` lines to commits. Do not sign commits with Claude as co-author.
- Keep commit messages concise and descriptive without any AI attribution.

## Git Branching Strategy

```
main (versioned, production — semantic-release)
  └── dev (integration branch)
        ├── feature/<name>  → PR to dev
        ├── feature/<name>  → PR to dev
        └── feature/<name>  → PR to dev
```

- `main` is protected. Only `dev` merges into `main` when all tests pass.
- `dev` is the integration branch. All feature work targets `dev`.
- Feature branches are created from `dev` and merged back via PR.
- NEVER work directly on the `main` branch.

## Workflow

- Always start every conversation in **plan mode**. Discuss the approach before writing code.
- Only exit plan mode and start implementing after the user confirms the plan.
- During plan mode, evaluate if the task would benefit from an agent mode and suggest it:
  - `/pair-programmer` — for features that benefit from TDD methodology (Red-Green-Refactor)
  - `/pedagogy` — when the user wants to understand decisions, learn concepts, and get exercises
- For multi-feature parallel work, use the orchestrator pipeline directly (no slash command needed).
- For small single-file changes, work directly on `dev` — no agent mode needed.

## Available Skills

### dbg (Debugger)

Use `dbg` when investigating runtime bugs, stepping through code, inspecting variables, or debugging test failures. Supports Node.js, Bun, and native code (C/C++/Rust via LLDB).

- Launch: `dbg launch --brk node app.js`
- Set breakpoint: `dbg break src/file.ts:42`
- Inspect state: `dbg state`
- Full reference: `~/.claude/skills/dbg/SKILL.md`

### find-skills (Skill Discovery)

**WARNING — SECURITY RISK**: This skill searches and installs third-party packages from the internet via `npx skills`. Installing external skills can introduce arbitrary code execution, supply chain vulnerabilities, and security breaches.

**Rules:**

- NEVER use `find-skills` proactively. Only use it when the user explicitly asks to find or install a skill.
- NEVER use it as a first resort. Exhaust all built-in tools, existing skills, and your own capabilities first.
- Only use it when you have genuinely found NO other solution to the user's problem.
- ALWAYS present the skill source, install count, and author to the user BEFORE installing anything.
- NEVER install a skill without explicit user approval.
- Prefer skills from verified sources (`vercel-labs`, `anthropics`, `microsoft`) with 1K+ installs.
- Treat unknown authors and low-install-count skills as untrusted.

## Token Optimization (rtk)

- Always prefix shell commands with `rtk` when rtk is installed (check with `rtk --version`).
- Use `rtk git status`, `rtk git diff`, `rtk git log`, `rtk ls`, `rtk grep`, etc. instead of raw commands.
- This saves 60-90% of tokens on command outputs.
- If rtk is not installed, use raw commands normally.

## Context7 MCP (Library Documentation)

- Context7 MCP is available. Use it automatically when you need up-to-date library/API documentation, code generation examples, or setup/configuration steps — without the user having to ask.
- If there is any chance information may be newer than your training knowledge, or if your confidence is low on a library/framework/API topic, use Context7 first before answering.
- Use `resolve-library-id` to find the Context7 library ID, then `query-docs` to fetch relevant documentation.
- This ensures code examples and API usage are current and version-accurate, avoiding hallucinated or outdated APIs.

## Learning from Mistakes (INTEL.md)

- At the start of every conversation, read `~/.config/opencode/INTEL.md` and apply all lessons listed there.
- Whenever the user corrects you or points out a mistake, immediately add a concise entry to `~/.claude/INTEL.md` describing what went wrong and how to avoid it in the future.
- Never repeat a mistake that is documented in INTEL.md.
