# INTEL - Lessons Learned

This file tracks mistakes and corrections so they are never repeated.

<!-- Format: - **[Category]**: Description of mistake -> What to do instead -->

- **[TDD]**: Wrote implementation code before tests -> ALWAYS write tests first (Red-Green-Refactor). Create the integration/unit test file, write failing tests for the expected behavior, then implement the code to make them pass. This applies to all feature work, not just when using /pair-programmer mode.
- **[Context Scope]**: Read from `~/.claude` during an OpenCode session -> In OpenCode sessions, only read/write inside `~/.config/opencode` unless the user explicitly asks for another path.
- **[Requirements Fidelity]**: Converted user issue wording incorrectly (CF-001/CF-008) -> Copy user-provided issue statements verbatim when requested and verify exact polarity/decision text before creating or editing GitHub issues.
- **[Shell Safety]**: Ran a pseudo-TTY prompt command that appeared to hang/infinite-loop -> Avoid scripted interactive prompt runs unless strictly needed; prefer deterministic non-interactive env-based reproduction and cap long-running command strategies.
- **[Scope Control]**: Logged issues for unimplemented/out-of-sprint areas (fullstack) -> Only record issues for currently implemented sprint scope unless the user explicitly asks for forward-looking backlog items.
- **[Requirement Drift]**: Kept old default-confirm assumption after user changed direction -> Treat latest user directive as source of truth and update issue text immediately (e.g., Enter default should be YES when requested).
- **[Test Execution]**: Ran multiple Vitest commands in parallel while coverage was enabled, causing `coverage/.tmp` write races -> Run Vitest commands sequentially (or in a single invocation) when coverage outputs share the same temp directory.
- **[Browser Validation]**: Treated terminal `curl` success as proof that frontend would load data -> When a browser frontend calls the API, always verify CORS with an `Origin` preflight/request before claiming the UI path works.
