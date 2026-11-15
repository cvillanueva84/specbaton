# Changelog

## Reviewer 0.2.0 and memory 0.4.1 · 2026-11-15

The pre-review adds a pass as the team's reviewer, and adopts the team's bar for what blocks.

Why: the reviewer agent reviews against the author's own account (proposal, specs, design and ADRs), so a case the spec misses, the review misses too. Most reviewer CLIs can't run code, and the calibration rewarded precision: Low meant "can come later", and a review with no findings was a valid result. In one team's learning runs, the pre-review caught none of the human reviewers' findings, all of them in passes that already existed. Ruled out: adding more questions to the skill after each pull request (that is what had been failing), pasting the team's rules into the agent's prompt alone (the agent would still read only the author's account and couldn't run code), and replacing the reviewer agent (it remains the review against the spec, the design and the ADRs).

- **Reviewer pass** (`prompts/reviewer-pass.md`). In round 1 of `/specbaton-reviewer:code`, while the reviewer agent runs, a `general-purpose` Claude subagent (`reviewer.pass_model`, `sonnet` by default, `off` to turn it off) reviews with a clean context and only what the team sees: the diff, the pull request's text, the ticket with its parent story or epic, and the RFC (each `none` when there isn't one), plus the code and its installed dependencies. It doesn't read `openspec/`, the memory layer, `plan.md` or any review. It lists at least 10 unfiltered candidates, verifies each by reading or by running the library in a scratch folder (no writes, installs, network or credentials), keeps findings whose trigger it can't confirm, and decides what blocks by what ships if the pull request merges as it is. Its output uses Conventional Comments labels, with the evidence and the dismissed candidates. The command checks `git status` of every repo before and after it.
- **Calibration.** Every finding cites file and line, and an unconfirmed trigger never drops it. High blocks, Medium is fixed in this pull request, Low is only what isn't a defect, and Hardening is protection against a state the system already prevents, saying what prevents it. A defect on a path the pull request touches is High or Medium, whatever the reason to wait. The validation prompt asks the agent to validate the pass's findings too.
- **`review.md` and the triage.** `review.md` holds the agent's output and then the pass's; `generated_by` adds the pass's model. The triage has one row per finding of both passes, with its origin (`A`, `T` or `A+T`), traces each trigger, runs the library when the opinion depends on it, checks every caller and the owning layer before proposing a fix, and reads the parent story before saying an acceptance criterion is missing. Later rounds keep the pass's section.
- **Lessons** (`references/lessons.md` in the review skill, from the template, seeded with seven generic rules). The reviewer pass applies them; `SKILL.md` doesn't reference them, so it stays self-contained and under 12 KB. `/specbaton-reviewer:code <change> learn` classifies against both passes, turns each `missed-*` and each repeated `out-of-scope` into a lesson (or updates it, saying the rule existed and wasn't applied), and changes `SKILL.md` only for a pattern seen in two pull requests or more, a High one, or a pass with false positives twice. The detection rate counts both passes.
- **Review skill template.** Rule 1 keeps findings whose trigger can't be confirmed; pass 1 traces each step of the pull request's test plan and runbooks; pass 7 wants a number's basis where reviewers read it (the pull request's text, the ticket or the RFC, not an ADR alone), and defaults to Medium. `SPEC.md` records how the lessons work and what the pass covers.
- **Memory 0.4.1: pull request rules** (`templates/cycle-rules.md`). Every number the diff adds or moves carries its measurement or derivation in Trade-offs or in the ticket, and a pull request's base, `mergeable` and head are checked before reporting it.

## 0.4.0 · 2026-11-06

Obsidian's graph view, colored by path.

- `obsidian.py --colors` proposes a color group per path (`.obsidian/graph.json`): `NOW.md`, the dashboard, ADRs, archived changes, changes in progress, specs, status, reference, pull request texts and templates, when they exist, plus each other first-level folder that isn't excluded. More specific paths come first (archived changes before changes), since Obsidian colors a note with the first group it matches.
- `/specbaton:setup` shows the proposed groups and adds them on yes (`--colors --apply`), after the vault's own groups, which it never changes. The answer is recorded as `"obsidian_colors"`.
- `check.py` reports the colors as to ask in a vault never asked about them, and as missing when a memory folder created later (say `pull-request/`) has no group yet.

## 0.3.0 · 2026-11-06

Choosing what gets a graph, and what Obsidian leaves out.

- `/specbaton:setup` shows every folder discovery looked at and why it is or isn't a unit (`graphs.sh --candidates`), then asks which units to leave out (`exclude`), which other folders to add (`include`, new: code without a manifest, such as scripts) and which platform graph to build: `merge` (the units' graphs merged, for several repos), `full` (one graph of the whole root, for a monorepo) or `none`. Discovery keeps running, so a folder added later still becomes a unit on its own.
- A `full` platform graph now leaves the excluded folders out. In layer W the platform graph is never `full`: the root's `.gitignore` hides the repos.
- `scripts/obsidian.py` sets Obsidian's excluded folders ("Files and links > Excluded files", `.obsidian/app.json`). The setup detects a folder that's already a vault, always excludes `graphify-out/`, suggests the code folders, repos and dependencies, and asks which to exclude. It keeps every other setting in `app.json`, creates it when the vault has none, and leaves a file in an unexpected shape alone.
- `check.py` reports an Obsidian vault that doesn't exclude `graphify-out/` yet, so a second setup fixes it.

## 0.2.1 · 2026-11-06

Running `/specbaton:setup` again brings a setup up to date instead of starting over.

- `scripts/check.py` lists what a project's setup has (`ok`), what it's missing (`missing`: a deleted file, an ignore never added, a unit without its graph), the optional features never offered (`ask`, such as the code graphs for a 0.1 setup) and the ones turned down (`off`). It only reads.
- `/specbaton:setup` runs it first. In a project that's already set up it shows what's in place and offers only what's missing or new, at one confirmation; it never asks the layer again. When there's nothing to do, it says so in one line.
- The settings record the optional features turned down (`"obsidian": false`, `"cycle_rules": false`, `"graphs": {"enabled": false}`), so a later setup doesn't ask about them again.
- The rules templates start with a `<!-- specbaton:… -->` marker that a later setup looks for. Rules written by 0.1 are recognized without it.
- `tests/setup.test.sh` covers a 0.1 setup, an up-to-date one, a deleted file, features turned on but not in place, and layer B.

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
