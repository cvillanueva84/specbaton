---
name: setup
description: Set up specbaton's memory layer in this project - detects the project's structure (several repos, a monorepo or a single repo), decides with the user where the memory lives, and creates NOW.md, the ADR folder, the rules and .claude/specbaton.json. Run it only when the user types /specbaton:setup or asks to set up specbaton.
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/graphs.sh" *)
---
Set up specbaton's memory in this project. The idea: **the chat is RAM and the repo is disk**. Decisions and the state of the work live in versioned files, and every session starts by reading them, so a compaction or a new chat loses nothing.

Reply in the user's language. Every file you create is in English unless the user asks for their own language (then translate the templates' text, keeping file names, frontmatter keys and the `[UNCERTAIN]` tag).

## Rules for this setup

- Work in phases. At each **⏸ CONFIRM**, show what you're about to do and wait for the user's approval.
- Never delete existing files. If a file you're about to create exists, don't overwrite it: show the diff and ask.
- Never commit, push or touch a team repo's history without the user's approval. Never stage `.env*`, keys or anything that looks like a secret.
- The templates are in `${CLAUDE_SKILL_DIR}/../../templates/`. Use them as they are, replacing `{{MEM}}` and `{{STATUS}}` with this project's values.

## Phase 1. Scan (read-only)

Run from the project root and report what you find:

```bash
pwd; ls -la
git rev-parse --show-toplevel 2>/dev/null && git remote -v && git log --format='%an' | sort | uniq -c | sort -rn | head -5
find . -maxdepth 3 -name .git -not -path './.git' 2>/dev/null | sed 's|/.git$||'
ls -la CLAUDE.md CLAUDE.local.md AGENTS.md .claude .claude/specbaton.json openspec 2>/dev/null
ls -ld .. && [ -w .. ] && echo "parent writable" || echo "parent NOT writable"
ls -d ../*-memory ../*-memoria 2>/dev/null
command -v openspec python3 git
```

Classify the topology:

| Topology | Signals |
| --- | --- |
| **T1. Multi-repo** | The root isn't a git repo (or is a personal one) and holds several folders with their own `.git` |
| **T2. Monorepo** | The root is a git repo with units inside (`apps/`, `packages/`, `services/`, workspaces) |
| **T3. Single repo** | The root is one git repo with one application |
| **T4. Hybrid** | The root is a git repo and also holds folders with their own `.git`. Ask how to treat it |

If `--show-toplevel` is a folder above this one, the project sits inside another repo: ask the user whether that repo is theirs before going on.

## Phase 2. Decide where the memory lives (⏸ CONFIRM)

| Layer | When | MEM | Rules file |
| --- | --- | --- | --- |
| **W** | T1: the root becomes a private git repo of its own, whose `.gitignore` ignores everything and allows only the memory files, so the team repos stay untouched | `.` | `CLAUDE.md` |
| **A** | T2/T3, when the repo is the user's or the team adopts the memory | `.` | `CLAUDE.md` |
| **B** | T2/T3 in a team repo the user doesn't want to change: a private repo beside it holds the memory | `../<project>-memory` (any path outside the repo; ask when the parent isn't writable; reuse a sibling memory repo when the scan found one) | `CLAUDE.local.md` |

Recommend one with the scan's signals: an organization remote, several authors or a team `CLAUDE.md` suggest B. Also confirm:
- **STATUS** (each change's state): `openspec/changes/{change}/status.md` with OpenSpec in layers W and A; `<MEM>/status/{change}.md` in layer B or without OpenSpec.
- **OpenSpec:** whether the project uses it (`openspec/` exists, or the user wants it).
- **Obsidian** (optional): a `dashboard.md` with Dataview views of the ADRs and changes.
- **Code graphs** (optional): a graphify graph per unit (repo, service or package), refreshed by the handoff, so Claude can ask about the code's structure instead of reading it file by file. Needs graphify.
- **Ticket cycle rules** (optional): test-first, local gate, pull request text, permissions and stacked branches (`templates/cycle-rules.md`). If the user wants them, ask what they need: the team's language for pull requests, the integration branch, the approvals a pull request needs, and the tracker.

## Phase 3. Create the layer (⏸ CONFIRM)

**Layer W.**
1. `git init` at the root, if it isn't a repo yet.
2. A `.gitignore` that allows only the memory files:
   ```gitignore
   # Private repo of the workspace's memory layer. Everything at the root is ignored except what's allowed below,
   # so every repo cloned here stays out of this one.
   /*
   !/.gitignore
   !/CLAUDE.md
   !/AGENTS.md
   !/NOW.md
   !/dashboard.md
   !/decisions/
   !/templates/
   !/docs/
   !/openspec/
   !/status/
   !/pull-request/
   !/.claude/
   /.claude/settings.local.json
   ```
3. Never add a remote unless the user asks: the layer may hold the company's content.

**Layer A.**
1. Ask whether the memory files are committed with the code (the team sees them) or kept out through `.git/info/exclude`.
2. Ignore what's generated locally: add `.obsidian/` (Obsidian's settings, written when the project is opened as a vault) and `graphify-out/` (the code graphs) to the repo's `.gitignore`, creating the file when it doesn't exist. When the team owns `.gitignore` and the memory files are kept out through `.git/info/exclude`, add them there instead.

**Layer B.**
1. Create the folder MEM and `git init` it.
2. Create `<MEM>/.gitignore` with `.obsidian/`: MEM is the vault in this layer.
3. Add to the team repo's `.git/info/exclude` (not shared): `CLAUDE.local.md`, `.claude/specbaton.json` and `graphify-out/`.

Ignore `.obsidian/` and `graphify-out/` whether or not the user picked Obsidian or the graphs now: it costs nothing and saves them from adding them by hand later. Layer W's allowlist already leaves both out.

## Phase 4. Memory files (⏸ CONFIRM)

Inside MEM create, from the templates:
- `NOW.md` (with today's date);
- `decisions/README.md` (from `decisions-README.md`);
- `templates/adr.md`;
- `docs/reference/README.md`, with one line: "Operational reference: environment, hosts, commands, test data and learned procedures. It isn't in the rules file to save context; Claude reads it when a task needs it."
- `status/` when STATUS lives there.

In the rules file at the project root (`CLAUDE.md`, or `CLAUDE.local.md` in layer B):
- If it exists, keep its content and add only what's new at the end.
- Add these imports at the top, keeping `@AGENTS.md` only when that file exists: `@AGENTS.md`, `@<MEM>/NOW.md`, `@<MEM>/decisions/README.md` (MEM relative to the project root, `.` written as nothing: `@NOW.md`).
- Append `templates/rules.md` with `{{MEM}}` and `{{STATUS}}` replaced.
- In layer W, add to "How I work": "The team repos aren't modified: git, builds and tests run from each repo's folder, and ADRs, state and OpenSpec are never written inside them."
- With the ticket cycle rules: append `templates/cycle-rules.md` with its placeholders filled in, and create `<MEM>/docs/reference/gates.md` with a `Unit | Folder | Tests | Lint | Type-check` table filled from what you find (Makefile targets, `package.json` scripts, `pytest`, `ruff`, `mypy`, `go test`…), marking `<FILL IN>` what you can't infer. Run each command once and note whether it passes, so it's clear which units already carry errors.

With OpenSpec, if `openspec/config.yaml` has no `context:`, propose one describing the project. In layer B it's the team's file: only propose it.

With Obsidian, copy `templates/dashboard.md` to the vault's root (the project root in W and A, MEM in B). In layer B or without OpenSpec, change the "State of the active changes" query to `FROM "status"` without the `file.name = "status" AND` condition, and drop "Open tasks by change". The user installs Dataview by hand.

## Phase 5. Settings file

Write `.claude/specbaton.json` at the project root (merge into it when it exists, keeping other keys, such as the reviewer's):

```json
{
  "version": 1,
  "layer": "<W|A|B>",
  "memory_dir": "<MEM, relative to the project root or absolute>",
  "rules_file": "<CLAUDE.md|CLAUDE.local.md>",
  "status_path": "<STATUS, with {change} where the change's name goes>",
  "openspec": <true|false>,
  "graphs": {"enabled": <true|false>, "units": "auto", "exclude": [], "platform": "auto"},
  "graphify_cmd": "",
  "farewell_patterns": []
}
```

`farewell_patterns` adds goodbyes in other languages (regular expressions, lowercase, without accents) to the built-in English and Spanish ones. `graphs.platform` is `merge`, `full`, `none` or `auto` (merge for several repos, full otherwise). `graphify_cmd` is only for a project that already has its own command to refresh the graphs; leave it empty to use specbaton's.

## Phase 6. Code graphs (optional, ⏸ CONFIRM)

Only when the user wants them.

1. **graphify.** Check `graphify --help` lists `update`, `merge-graphs`, `cluster-only` and `export wiki`. If graphify is missing or older, ask the user to install it (don't install it yourself): `pipx install graphifyy` (or `pipx upgrade graphifyy`; the package has two y's and the command is `graphify`), and check again once they confirm.
2. **Units.** A unit is a folder with a graph of its own: a repo, a service or a package. With the graphs turned on in the settings (`"graphs": {"enabled": true}`, phase 5), show the user what discovery finds: `bash "${CLAUDE_SKILL_DIR}/../../scripts/graphs.sh" --list`.
   - Several repos in one folder: each repo is a unit, and the platform graph merges them.
   - A monorepo: each first-level folder with a project manifest (`package.json`, `pyproject.toml`, `go.mod`…) is a unit, and so is each such folder one level down (`apps/web`); the platform graph covers the whole root, which keeps the real imports between units.
   - A single app: no units; the root's graph is the only one.

   Discovery runs every time, so a folder added later becomes a unit on its own. If the user wants other units, set `"units": {"<name>": "<path>", …}` (then only those count), or leave out folders with `"exclude": ["<path>", …]`. Infrastructure code (Terraform, Helm, YAML) comes out empty with graphify's AST extraction: leave such folders out.
3. **First build.** Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/graphs.sh"` and show `graphify-out/INDEX.md`. No unit should have 0 nodes, apart from folders without code.
4. **Rules.** Append `templates/graphs-rules.md` to the rules file.
5. **Cursor** (only when the project has `.cursor/` or the user uses Cursor): create `.cursor/rules/graphify-workspace.mdc` saying the platform graph is `graphify-out/graph.json`, each unit's is `graphify-out/units/<unit>/graphify-out/graph.json` with a wiki beside it, and `graphify update` must not be run by hand. Tell the user not to run `graphify cursor install`: it rewrites graphify's own rule. In layer B, add the file to the team repo's `.git/info/exclude`.

## Phase 7. Check and commit (⏸ CONFIRM)

```bash
python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" "$PWD"
```

It must print the values you wrote, with `memory_dir_abs` pointing to MEM. Also check that Obsidian's folder is ignored: `git -C <MEM> check-ignore -q .obsidian/ && echo "obsidian ignored"` must print the message, and likewise `git check-ignore -q graphify-out/` from the project root. Then show `git -C <MEM> status`, check that no secret is staged (`git -C <MEM> diff --cached --name-only | grep -iE '\.env|secret|\.pem|\.key'` prints nothing), and propose the first commit of the memory layer.

## Phase 8. Tell the user how it works

- A new session (or `/clear`) starts with a summary of where things stand: a hook asks for `/specbaton:resume-work` before the first answer.
- Decisions become ADRs as they're made, always `proposed`; the user moves them to `accepted`.
- `/specbaton:handoff` writes the state, the ADRs, the indexes and the tasks, and proposes the commit. It also runs on its own when the user says goodbye.
- After a compaction, a hook re-anchors the session on the files.
- One change per session: before switching topics, `/specbaton:handoff` and `/clear`.
- With code graphs: the handoff refreshes the graphs of the units the session touched, and a new folder gets its graph the first time a session works in it. `graphs.sh --list` shows the units.
- Optional next step: the `specbaton-reviewer` plugin adds a second agent that writes the plan and reviews the code, read-only (`/specbaton-reviewer:setup`).
