# AGENTS.md

Rules for any agent (or person) making changes in this repository.

## 1. Question every feature request before writing requirements

- When a feature is requested, ask the requester detailed questions before
  writing any product requirements.
- Keep asking until every aspect is covered: goals, users, use cases, inputs
  and outputs, edge cases, error handling, data, UI, performance, security,
  and how the feature fits with existing features.
- Do not write requirements, tests, or code while an important question is
  still open.

## 2. Write tests first for every new feature

- Before writing any feature code, write the tests for it.
- The tests must cover every use case the feature asks for. That includes the
  normal path, edge cases, invalid input, and error handling.
- Run the new tests and confirm they fail before you start the implementation.
- The feature is complete only when all of its tests pass.

## 3. Design the UI concept for each module before writing code

- After the tests are written and before any code is written, design the UI
  concept for each module that has a user interface.
- Decide the screens, layout, main components, user flows, and the states
  each screen can be in (empty, loading, error, success).
- Get the UI concept agreed on before writing the module's code.

## 4. Keep code modular

- Split the code into modules so each feature depends on as little of the
  rest of the codebase as possible.
- Give each module one clear job and a small, well-defined interface.
- Do not reach into another module's internals. Use its public interface.
- Avoid circular dependencies and shared global state between modules.

## 5. Use tests to keep the codebase small

- Use the tests to find code that isn't needed: remove a piece of code and run
  the tests.
- If the tests still pass, the code is either unneeded or untested. Delete it
  if it's unneeded. If it's needed, add a test that fails without it.
- Prefer the smallest amount of code that passes all tests.

## 6. Commit every change

- Make a git commit after every change, so each change can be tracked and
  rolled back later.
- Keep each commit focused on one change, and write a message that says what
  changed and why.
- Never leave finished work uncommitted.

## 7. Run the full test suite after every change

- After every change, run the tests for all modules, not only the module you
  changed, to confirm nothing else broke.
- If any test fails, fix it before moving on.

## 8. Deliver only when every test passes

- All tests must pass before delivery.
- Do not skip, disable, or delete a test to get the suite passing.

## 9. Keep local and online versions in sync

- If the software has both a local version and an online version, their data
  must stay in sync.
- Both versions must run the latest software. Deploy or update both whenever
  a change ships.
