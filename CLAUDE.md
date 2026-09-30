# CLAUDE.md

## Development workflow (required)
- New feature or change request with no spec/ticket → stop and ask the dev to run
  `/grill-with-docs` first. Don't write code until it's done.
- After grilling: multi-session work → `/to-spec`, then `/to-tickets`; small work → `/implement`.
- All implementation is test-first (`/tdd`). Run `/code-review` before committing.
- Hard bugs → `/diagnosing-bugs`. Unsure which skill fits → suggest `/ask-matt`.
- Use the terms in CONTEXT.md and respect the ADRs in docs/adr/.

Skills live in `.claude/skills/` (vendored from mattpocock/skills; see its README). Before the first engineering flow in this repo, run `/setup-matt-pocock-skills`.
