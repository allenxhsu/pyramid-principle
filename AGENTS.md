# AGENTS.md

Rules for any agent (or person) making changes in this repository.

## 1. Write tests first for every new feature

- Before writing any feature code, write the tests for it.
- The tests must cover every use case the feature asks for. That includes the
  normal path, edge cases, invalid input, and error handling.
- Run the new tests and confirm they fail before you start the implementation.
- The feature is complete only when all of its tests pass.

## 2. Commit every change

- Make a git commit after every change, so each change can be tracked and
  rolled back later.
- Keep each commit focused on one change, and write a message that says what
  changed and why.
- Never leave finished work uncommitted.

## 3. Run the full test suite after every change

- After every change, run the tests for all modules, not only the module you
  changed, to confirm nothing else broke.
- If any test fails, fix it before moving on.

## 4. Deliver only when every test passes

- All tests must pass before delivery.
- Do not skip, disable, or delete a test to get the suite passing.

## 5. Keep local and online versions in sync

- If the software has both a local version and an online version, their data
  must stay in sync.
- Both versions must run the latest software. Deploy or update both whenever
  a change ships.
