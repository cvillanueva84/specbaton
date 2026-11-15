# specbaton

A Claude Code plugin marketplace with two plugins that install separately. `README.md` is the user manual; `CHANGELOG.md` records each release and why it was made.

## Layout

| Path | What |
| --- | --- |
| `.claude-plugin/marketplace.json` | Marketplace listing (no versions here) |
| `plugins/specbaton/` | Memory plugin: `skills/` (setup, resume-work, handoff, implement), `hooks/`, `scripts/`, `templates/` |
| `plugins/specbaton-reviewer/` | Reviewer plugin: `skills/` (setup, plan, code), `prompts/`, `scripts/`, `templates/review-skill/` |
| `tests/*.test.sh` | Plain bash tests, one file per area |

## Commands

| Task | Command |
| --- | --- |
| Hooks, `config.py` | `bash tests/hooks.test.sh` |
| `check.py`, `obsidian.py` (a second setup) | `bash tests/setup.test.sh` |
| `units.py`, `graphs.sh` | `bash tests/graphs.test.sh` (real build only when `graphify` is installed) |
| `tasks.py`, `snapshot.sh`, the implementer prompt, every skill's `allowed-tools` | `bash tests/implement.test.sh` |
| Reviewer wrapper, stream parser, `change_diff.sh`, review skill template | `bash tests/reviewer.test.sh` |
| Manifests | `claude plugin validate .` |
| Try local changes in a real session | `claude --plugin-dir ./plugins/specbaton --plugin-dir ./plugins/specbaton-reviewer` |

- Tests print `ok`/`FAIL` lines and exit non-zero on any failure. They use throwaway projects (`mktemp -d`) and fake CLIs: no network, no model calls.
- A script change comes with a test in the matching `tests/*.test.sh`.
- The installed plugins (`~/.claude/plugins/cache/`) don't change when this repo does. They change only after a push and `claude plugin update`.

## Releasing

- Each plugin has its own version in `plugins/<plugin>/.claude-plugin/plugin.json`. Bump only the plugins that changed (pre-1.0: a feature is minor, a fix is patch).
- In the same commit:
  - a `CHANGELOG.md` entry on top: `## <version> · <YYYY-MM-DD>`, or `## Reviewer X and memory Y · <date>` when both change;
  - README's version badge (the memory plugin's version) and the version line under "Development";
  - every README section the change affects (Commands, Settings, the reviewer table, Troubleshooting).
- Design changes get a "Why:" and a "Ruled out:" in the CHANGELOG entry, like an ADR.
- Commit subject: one plain sentence, versions in parentheses, for example `Color Obsidian's graph view by path (0.4.0)`.

## Writing skills, prompts, templates and docs

- Everything in the repo is in English. Skills tell Claude to reply in the user's language, and to write the user's files in English unless the user asks otherwise.
- Plain style: short sentences, contractions, "for example" or "such as" instead of "e.g.", terms defined on first use, no marketing. Match the text around the edit.
- Skill bodies are imperative instructions to Claude. Steps that need the user's approval are marked **⏸ CONFIRM**. Never commit, push or delete without approval.
- A skill's frontmatter `description` says when it runs: the explicit command, or the trigger it reacts to.
- Every script a skill runs is in its `allowed-tools`, as `Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/<script>" *)`.
- Every `{{PLACEHOLDER}}` in `prompts/` and `templates/` is replaced by the skill that copies the file. Add a new one in both places.
- A skill meant to run unattended reads nothing from its plugin's other folders with the Read tool. An installed plugin sits under `~/.claude/plugins/`, outside the project, so that read asks for permission, or is blocked in a headless run and stops the skill (it happened to `/specbaton:implement`). Such a skill runs its scripts through `allowed-tools` and keeps a subagent's prompt in its own `SKILL.md`. The interactive skills (the setups, handoff, the reviewer's plan and code) still read `templates/` and `prompts/`, where the user can approve the read.

## Scripts and hooks

- Only bash, the python3 standard library, git and perl (`change_diff.sh`). They must run on macOS (BSD tools) and Linux.
- Hooks source `plugins/specbaton/hooks/lib.sh` and fail open: they print nothing and exit 0 without `.claude/specbaton.json`, without `python3`, or with `SPECBATON_CHILD=1` (set by the reviewer wrapper).
- Hooks only add text to the session. The memory plugin sends nothing anywhere; only the reviewer sends the diff and files to the chosen CLI. Keep README's Privacy paragraph true.
- Each script's header comment documents its usage and exit codes, and skills depend on them (wrapper `0/2/3/4/5`, stream parser `6`, `config.py` and `check.py` `0/1/2`). Change a code only together with every skill that handles it.
- The reviewer's read-only guarantee is the wrapper's git snapshot before and after the run. Each adapter's flags are documented in the header of `reviewer_readonly.sh` and in README's reviewer table, and were checked by hand against the real CLIs in 2026-11. Check them by hand again when an adapter's flags change.

## Settings and upgrades

- A project's settings live in its `.claude/specbaton.json`, read by `plugins/specbaton/scripts/config.py` and `plugins/specbaton-reviewer/scripts/reviewer_config.py`.
- A new setting goes in that script's `DEFAULTS`, in the settings JSON of the setup skill that writes it, and in README's Settings block.
- Running `/specbaton:setup` again brings a setup up to date, through `plugins/specbaton/scripts/check.py`:
  - a new optional feature shows as `ask` in a setup that never offered it;
  - a declined feature is recorded as `false` and shows as `off`;
  - a part of the chosen setup that isn't there shows as `missing`;
  - each case is covered in `tests/setup.test.sh`.
- Rules templates start with a `<!-- specbaton:<name> -->` marker that `check.py` looks for. Keep its fallbacks for files written by 0.1.
- `plugins/specbaton-reviewer/templates/review-skill/SKILL.md` goes whole into the reviewer's prompt: it stays under 12 KB and never references `references/lessons.md` (the test checks both).
