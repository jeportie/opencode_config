# INTEL - Lessons Learned

This file tracks mistakes and corrections so they are never repeated.

<!-- Format: - **[Category]**: Description of mistake -> What to do instead -->

- **[TDD]**: Wrote implementation code before tests -> ALWAYS write tests first (Red-Green-Refactor). Create the integration/unit test file, write failing tests for the expected behavior, then implement the code to make them pass. This applies to all feature work, not just when using /pair-programmer mode.
