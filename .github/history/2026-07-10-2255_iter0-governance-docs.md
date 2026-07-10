# Project governance and planning docs

- **Date:** 2026-07-10 22:55
- **Iteration:** 0
- **Commit:** 3678cca

## What changed

Moved the requirements and workflow plan into `docs/`, and added the
project-specific agent instructions and skills under `.github/`.

## Why

This establishes the source-of-truth requirements, iteration plan, and
commit/history discipline required before starting Iteration 0 implementation.

## Files touched

- .github/AGENTS.md
- .github/skills/
- docs/requirements.md
- docs/workflow_plan.md

## Verification

- [ ] `flutter analyze` clean
- [ ] `flutter test` passing
- [ ] Manual on-device check needed? no
