# Changelog

## 0.2.0 · 2026-11-06

Code graphs, refreshed by the handoff.

- `scripts/graphs.sh` builds a graphify graph per unit (repo, service or package) plus a platform graph, and `graphify-out/INDEX.md`. It's the per-unit layout of the workflow this plugin packages, now inside the plugin.
- Units are discovered on every run (`scripts/units.py`): folders with their own `.git` in a multi-repo workspace, or folders with a project manifest (`package.json`, `pyproject.toml`, `go.mod`…) at the first level or one level down in a monorepo. A folder added later becomes a unit with no change to the settings, and `/specbaton:handoff` gives it its first graph the first time a session touches it. `"graphs": {"units": {…}}` sets them by hand, and `"exclude"` leaves folders out.
- The platform graph merges the units' graphs when they're separate repos, and covers the whole root otherwise, which keeps the real imports between units (`"platform"` overrides it).
- `/specbaton:setup` offers the graphs, checks graphify, shows the discovered units, runs the first build, adds the graph rules to the rules file and ignores `graphify-out/` (`.gitignore` in layer A, the team repo's `.git/info/exclude` in layer B, the allowlist already in layer W).
- `tests/graphs.test.sh` covers discovery in a multi-repo workspace, a monorepo, a folder added later, excluded and same-name units, a single app and units set by hand, plus a real build when graphify is installed.

## 0.1.1 · 2026-11-06

- `/specbaton:setup` makes the repo that holds the vault ignore `.obsidian/`: in the project's `.gitignore` in layer A (or `.git/info/exclude` when the team owns `.gitignore`), and in the memory repo's `.gitignore` in layer B. Layer W's allowlist already left it out. Before, a user who opened the folder in Obsidian had to add it by hand.

## 0.1.0 · 2026-11-06

First release, packaging the author's spec-driven workflow as two Claude Code plugins.

- **specbaton:** `/specbaton:setup` detects the project's structure and creates the memory layer (W, A or B); `/specbaton:resume-work` and `/specbaton:handoff`; hooks that ask for resume-work at the start of a session, re-anchor after a compaction and run the handoff when the user says goodbye (English and Spanish built in, more through `farewell_patterns`).
- **specbaton-reviewer:** `/specbaton-reviewer:setup`, `/specbaton-reviewer:plan` and `/specbaton-reviewer:code` (review, `validate`, `learn`); a wrapper with adapters for Cursor, Antigravity, Claude and any custom CLI, checked with a git snapshot and a search for changed files; a generic review skill template with 13 passes.
