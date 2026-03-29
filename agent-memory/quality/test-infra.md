# tskickstart quality baseline

- Test runner: `npm test` (Vitest, full suite)
- Integration suite script: `npm run test:integration`
- Coverage script: `npm run test:coverage` (Vitest v8)
- Lint: `npm run lint` (ESLint)
- Dedicated typecheck script: not configured in root `package.json`
- Coverage baseline observed (2026-03-28):
  - Statements: 41.66%
  - Branches: 66.33%
  - Functions: 53.84%
  - Lines: 41.66%
- Common non-blocking lint warning seen: `release.config.mjs` unused `eslint-disable` directive.
