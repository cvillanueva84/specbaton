# Changelog

## 0.1.1 · 2026-11-06

- `/specbaton:setup` makes the repo that holds the vault ignore `.obsidian/`: in the project's `.gitignore` in layer A (or `.git/info/exclude` when the team owns `.gitignore`), and in the memory repo's `.gitignore` in layer B. Layer W's allowlist already left it out. Before, a user who opened the folder in Obsidian had to add it by hand.

## 0.1.0 · 2026-11-06

First release, packaging the author's spec-driven workflow as two Claude Code plugins.

- **specbaton:** `/specbaton:setup` detects the project's structure and creates the memory layer (W, A or B); `/specbaton:resume-work` and `/specbaton:handoff`; hooks that ask for resume-work at the start of a session, re-anchor after a compaction and run the handoff when the user says goodbye (English and Spanish built in, more through `farewell_patterns`).
- **specbaton-reviewer:** `/specbaton-reviewer:setup`, `/specbaton-reviewer:plan` and `/specbaton-reviewer:code` (review, `validate`, `learn`); a wrapper with adapters for Cursor, Antigravity, Claude and any custom CLI, checked with a git snapshot and a search for changed files; a generic review skill template with 13 passes.
