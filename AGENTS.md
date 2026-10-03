# Dayline

Read `DAYLINE_WORKING_MEMORY.md` and `docs/DEVELOPMENT.md` before changing code.

- Update the current alignment entry with intent, affected execution chain and
  invariants before a behavior change; record actual verification afterward.
- Change the authoritative implementation. Keep one owner for state and input.
- Prefer deletion and direct code over wrappers, parallel paths and frameworks.
- Tests use temporary state files. Run `./scripts/check.sh` before handoff.
- Record source, package and installed-app verification separately. Tests do not
  establish physical trackpad or Spaces behavior.
