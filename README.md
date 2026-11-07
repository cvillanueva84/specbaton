<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img alt="SpecBaton" src="assets/logo-light.svg" width="480">
</picture>

# SpecBaton

Spec-driven development with Claude Code, passed like a baton: from one session to the next, and from the agent that implements to an agent that reviews.

- **`specbaton`** keeps the work's memory in versioned files, so a compaction or a new chat loses nothing: decisions as ADRs, one change per session, and two rituals, resume-work and handoff, triggered by hooks.
- **`specbaton-reviewer`** adds a second agent, run from the command line, that writes the implementation plan before Claude implements and reviews the diff afterwards. It only reads, and a wrapper proves it with a git snapshot. It can be Cursor, Antigravity, Claude with another model, or any CLI you configure.

The two plugins install separately: the memory works on its own, and the reviewer is for those who have, or want, a second agent.

## Why

Long agent chats get compacted, and the first thing a summary drops is *why*: the alternatives that were ruled out. A new chat then reopens decisions that were already made. And when the same model implements and reviews, its blind spots repeat. SpecBaton answers those three problems with four ideas:

1. **Files are the memory.** The present lives in `NOW.md` and a status file per change; decisions live in ADRs. A new session resumes from them.
2. **The spec comes before the code.** Each piece of work is a change (an OpenSpec change when the project uses it): proposal, specs, design and tasks.
3. **A second opinion that can't touch anything.** The reviewer agent writes the plan and reviews the diff, read-only and verified.
4. **The human decides what can't be undone.** ADRs are proposed and the user accepts them; the user decides each review finding, marks pull requests ready and merges.

## Quick start

Requires Claude Code, `git` and `python3`. The code graphs need graphify (`pipx install graphifyy`), and the reviewer's learning step uses `gh` and `jq`.

```bash
claude plugin marketplace add cvillanueva84/specbaton
claude plugin install specbaton@specbaton
claude plugin install specbaton-reviewer@specbaton   # optional
```

Then, in your project:

1. `/specbaton:setup` detects the project's structure (several repos, a monorepo or a single repo), decides with you where the memory lives, and creates it.
2. `/specbaton-reviewer:setup` (optional) finds the CLIs you have, asks which one reviews and with which models, creates your team's review skill, and tests it for real.
3. Work as usual. Every new session opens with a summary of where things stand; say goodbye and the handoff runs on its own.

After updating the plugin (`claude plugin marketplace update specbaton`), run `/specbaton:setup` again: it keeps what's there and offers only what's new.

## Commands

| Command | When | What it does |
| --- | --- | --- |
| `/specbaton:setup` | Once per project, and again after an update | Detects the structure, creates the memory layer and `.claude/specbaton.json`. In a project already set up, offers only what's missing or new |
| `/specbaton:resume-work [change]` | A hook asks for it at the start of every session; also by hand | Proposes the pending commit, reads `NOW.md`, the change's status and its ADRs, checks git since the last handoff, and summarizes |
| `/specbaton:handoff [change]` | When you say goodbye (a hook asks for it), when the context gets heavy, or before switching changes | Writes the status, creates the missing ADRs as `proposed`, updates the indexes and tasks, and proposes the commit |
| `/specbaton-reviewer:setup` | Once per project | Chooses the reviewer CLI and models, creates the review skill, runs three real read-only tests |
| `/specbaton-reviewer:plan <change>` | Right after proposing a change | The reviewer writes `plan.md`; Claude sends back only verifiable gaps, up to 3 rounds in the same conversation |
| `/specbaton-reviewer:code <change>` | Right after opening a draft pull request | The reviewer reviews the diff; Claude adds a triage where you decide each finding |
| `/specbaton-reviewer:code <change> validate` | After the fixes | The reviewer validates each fix in the same conversation, until the review closes |
| `/specbaton-reviewer:code <change> learn` | When the team comments on the pull request | Classifies what humans found that the agent missed, and proposes improvements to the review skill |

## The memory

```text
<memory layer>/
├── NOW.md                 active epics and changes; the session's starting point
├── decisions/
│   ├── README.md          one line per ADR
│   └── 0001-….md          one decision per file: proposed → accepted → superseded
├── templates/adr.md
└── docs/reference/        operational reference, read on demand
openspec/changes/<change>/
├── status.md              a snapshot of the present, not a diary
├── plan.md                from the reviewer (optional)
└── review.md              from the reviewer (optional)
```

Where the memory layer lives depends on the project. `/specbaton:setup` detects it and asks:

| Layer | For | What it does |
| --- | --- | --- |
| **W** | A folder with several repos | The root becomes a private git repo whose `.gitignore` allows only the memory files; the team repos stay untouched |
| **A** | Your own repo, or one whose team adopts the memory | The memory lives in the repo |
| **B** | A team repo you don't want to change | The memory lives in a private repo beside it; the rules go in `CLAUDE.local.md`, kept out of git |

**Code graphs** (optional, with [graphify](https://pypi.org/project/graphifyy/)): a graph per unit (a repo, a service or a package) under `graphify-out/units/`, plus a platform graph, so Claude asks about the code's structure instead of reading it file by file. Units are discovered on every run (repos in a multi-repo folder, or folders with a `package.json`, `pyproject.toml`, `go.mod`… in a monorepo), so a folder you add later gets its graph the first time a session works in it: `/specbaton:handoff` refreshes the graphs of the units a session touched. The setup shows what it found and lets you leave units out (`exclude`) or add folders it missed (`include`). Besides each unit's graph there's a platform graph for questions that cross units: the units' graphs merged (`merge`, the default for several repos) or one graph of the whole root (`full`, the default for a monorepo, which keeps the real imports between units).

**Obsidian** (optional): open the memory layer as a vault for a dashboard of ADRs and changes. The setup sets the folders Obsidian leaves out of its search and graph view: always `graphify-out/`, plus the code folders you choose. It can also color the graph view by path: ADRs, changes, specs, status and each folder of yours in its own color.

Rules for ADRs: the rejected alternatives are required (they're what a summary drops), an accepted ADR is never contradicted (a new one supersedes it), and an accepted ADR's body is never edited.

## The reviewer

| `cli` | Tool | How it stays read-only | Resumes with |
| --- | --- | --- | --- |
| `cursor` | Cursor (`cursor-agent`) | `--mode=ask`, never `--force` | `--resume=<id>` |
| `agy` | Antigravity (`agy`) | Session-only `--settings` with deny rules for commands, writes, MCP and URLs | `--conversation <id>` |
| `claude` | Claude Code with another model | `--tools "Read,Grep,Glob"`, no MCP tools, no user or project settings (so no hooks or plugins) | `--resume <id>` |
| `custom` | Any CLI | Its own read-only mode | When it supports it; otherwise each round carries the previous output |

Whatever the CLI, the real guarantee is the wrapper's: a git snapshot of the root, every nested repo and an external memory layer before and after the run, plus a search for files changed during it. If anything changed, it stops with exit code 4 and reverts nothing.

A reviewer from another model family brings other blind spots. Claude reviewing Claude works, and still brings a session with no memory of how the code was written, but it shares more of them: pick at least a different model, and remember it spends from the same account.

**Privacy.** The diff, the specs and the files the reviewer reads go to the CLI you choose, under your own account with that tool. The wrapper masks the usual secrets in the diff (`.env`-style keys, PEM keys, known token prefixes), but check what you send.

## Settings

Everything lives in `.claude/specbaton.json`, written by the setup skills:

```json
{
  "version": 1,
  "layer": "W",
  "memory_dir": ".",
  "rules_file": "CLAUDE.md",
  "status_path": "openspec/changes/{change}/status.md",
  "openspec": true,
  "graphs": {"enabled": true, "units": "auto", "exclude": [], "include": [], "platform": "auto"},
  "obsidian": true,
  "obsidian_colors": true,
  "cycle_rules": false,
  "farewell_patterns": [],
  "reviewer": {
    "cli": "agy",
    "plan_model": "…",
    "review_model": "…",
    "base": "origin/main",
    "skill": "acme-code-review",
    "exclude": [".obsidian"],
    "max_rounds": 3
  }
}
```

## Status

Version 0.4.0, early.

- `bash tests/hooks.test.sh` checks the memory plugin's hooks and settings with simulated hook inputs.
- `bash tests/setup.test.sh` checks how a second setup finds what's in place, what's missing and what's new.
- `bash tests/graphs.test.sh` checks how units are discovered for the code graphs, and builds real graphs when graphify is installed.
- `bash tests/reviewer.test.sh` checks the wrapper with fake CLIs for the four adapters: answers, resume flags, denied actions, writes inside repos and inside ignored folders, unknown models, usage limits and secret masking.
- The read-only behavior of each real CLI was checked by hand in November 2026, against Cursor's CLI, Antigravity 1.5.1 and Claude Code 2.1.

## License

MIT. See [LICENSE](LICENSE).
