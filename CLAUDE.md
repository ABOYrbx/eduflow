# CLAUDE.md

@AGENTS.md

This file points at `AGENTS.md`, which is the single source of truth for this
project. Read it before making changes.

## Notes that are easy to get wrong

- **`apps/web/AGENTS.md` is not a second source of truth.** It exists to warn
  that this Next.js version (16.3.6) has breaking changes and that
  `node_modules/next/dist/docs/` - resolved from the web workspace - is
  authoritative. That block is re-added by `next dev`; leave it in place.
- **The Prisma MCP server runs from the repo root** but your schema lives in
  `apps/api/prisma/`. Pass `projectCWD: "apps/api"` to `migrate-status`,
  `migrate-dev`, and `migrate-reset`, or they will not find the schema.
- **`migration/check-catalogs.py` is a German-residue detector**, not a
  key-parity checker. Passing it does not mean your catalogs agree with each
  other across platforms.
- **Use the `verify` skill** rather than assembling check commands by hand.
- **`scripts/check-version.sh` requires a pinned Gradle 8.7.** The path is in
  the skill; do not let Gradle fetch a different distribution.