<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="SpecBaton" src="assets/logo-light.svg" width="480">
  </picture>
</p>

<p align="center">
  Spec-driven development with Claude Code, passed like a baton:<br>
  from one session to the next, and from the agent that implements to an agent that reviews.
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="Version 0.5.1" src="https://img.shields.io/badge/version-0.5.1-informational">
  <img alt="Claude Code plugins" src="https://img.shields.io/badge/Claude%20Code-plugins-d97757">
</p>

SpecBaton is two [Claude Code](https://code.claude.com) plugins that install separately:

- **`specbaton`** keeps the work's memory in versioned files, so a compaction or a new chat loses nothing: decisions as ADRs, one change per session, and two rituals, resume-work and handoff, triggered by hooks. It can also hand a change's tasks to a subagent on a cheaper model while the session checks each one. It works on its own.
- **`specbaton-reviewer`** adds a second agent, run from the command line, that writes the implementation plan before Claude implements and reviews the diff afterwards. It only reads, and a wrapper proves it with a git snapshot. It can be Cursor, Antigravity, Claude with another model, or any CLI you configure.

## Why

Long agent chats get compacted (Claude Code summarizes the conversation when the context fills up), and the first thing a summary drops is *why*: the alternatives that were ruled out. A new chat then reopens decisions that were already made. And when the same model implements and reviews, its blind spots repeat. SpecBaton answers those three problems with four ideas:

1. **Files are the memory.** The present lives in `NOW.md` and a status file per change; decisions live in ADRs (Architecture Decision Records: one short file per decision, with the alternatives that were rejected). A new session resumes from them.
2. **The spec comes before the code.** Each piece of work is a *change*: proposal, specs, design and tasks, written with [OpenSpec](https://github.com/Fission-AI/OpenSpec) when the project uses it.
3. **A second opinion that can't touch anything.** The reviewer agent writes the plan and reviews the diff, read-only and verified.
4. **The human decides what can't be undone.** ADRs are proposed and you accept them; you decide each review finding, mark pull requests ready and merge.

## How it works

Every session works on one change, and starts and ends the same way:

```mermaid
flowchart LR
    S([New session or /clear]) -->|hook| R["/specbaton:resume-work<br/>reads NOW.md, the change's status<br/>and its ADRs, checks git"]
    R --> W["You and Claude work<br/>on one change"]
    W -->|a decision is made| D["ADR written as proposed<br/>you accept it"]
    D --> W
    W -->|you say goodbye,<br/>or the context gets heavy| H["/specbaton:handoff<br/>writes the status, ADRs, indexes,<br/>tasks and code graphs"]
    H --> C["Commit of the memory,<br/>with your approval"]
    C -.->|next session| S
```

The chat is RAM and the repo is disk: whatever must survive is in a file by the time the session ends.

## Quick start

Requires Claude Code (tested with 2.1), `git`, `python3` and `bash`, on macOS or Linux. Optional: [OpenSpec](https://github.com/Fission-AI/OpenSpec) for changes (`npm install -g @fission-ai/openspec@latest`; the reviewer's plan needs it), [graphify](https://pypi.org/project/graphifyy/) for code graphs (`pipx install graphifyy`), and `gh` and `jq` for the reviewer's learning step.

From your shell:

```bash
claude plugin marketplace add cvillanueva84/specbaton
claude plugin install specbaton@specbaton
claude plugin install specbaton-reviewer@specbaton   # optional
```

Or inside a Claude Code session: `/plugin marketplace add cvillanueva84/specbaton`, then `/plugin install specbaton@specbaton`.

Then, in your project:

1. `/specbaton:setup` detects the project's structure (several repos, a monorepo or a single repo), decides with you where the memory lives, and creates it. Every step is shown before it runs, and nothing is committed without your approval.
2. `/specbaton-reviewer:setup` (optional) finds the CLIs you have, asks which one reviews and with which models, creates your team's review skill, and tests it for real.
3. Start a new session. It opens with a summary of where things stand.

## Usage guide

### A change, from start to finish

```mermaid
sequenceDiagram
    actor You
    participant C as Claude
    participant R as Reviewer (read-only)
    participant I as Implementer (Sonnet)
    You->>C: Propose the change (/opsx:propose)
    C->>R: /specbaton-reviewer:plan
    R-->>C: plan.md
    C->>R: Verifiable gaps only, up to 3 rounds
    R-->>C: Corrected plan
    C->>You: Implement with Sonnet, by groups?
    You->>C: Yes
    loop Each group of tasks
        C->>I: The group's tasks
        I-->>C: The code and its report
        Note over C: Checks the diff, runs the<br/>verification, compares the spec
    end
    Note over C: Decisions become ADRs (proposed)
    C->>C: Draft pull request
    C->>R: /specbaton-reviewer:code
    Note over C: In parallel, a Claude subagent reviews<br/>as the team would, with only what the team sees
    R-->>C: review.md
    C->>You: Triage of each finding
    You->>C: Your call on each one
    C->>R: /specbaton-reviewer:code … validate
    R-->>C: Each fix checked, review closed
    You->>You: Mark ready and merge
```

Step by step, for your first change:

1. **Open a session in the project.** A hook asks Claude to resume: it reads `NOW.md`, says where you left off and waits. The first time, `NOW.md` is empty.
2. **Propose the change.** With OpenSpec, `/opsx:propose <what you want>` writes the proposal, specs, design and tasks under `openspec/changes/<change>/`. Without it, describe the change and Claude tracks it in its status file.
3. **Get a plan** (with the reviewer). `/specbaton-reviewer:plan <change>`: the reviewer writes `plan.md`, and Claude sends back only what it can prove is missing (a scenario the plan doesn't cover, a path that doesn't exist), for up to 3 rounds.
4. **Implement.** With delegated implementation on, Claude offers `/specbaton:implement <change>`: a subagent on a cheaper model (Sonnet by default) implements each group of tasks, and the session checks each group before checking it off. It reads the group's diff, runs its verification itself and compares it with the spec. It stops only for a problem in the spec or in the environment: a group that still fails after `max_retries` rounds (2 by default) is fixed by the session itself, which then goes on. Or say no and work as usual. When you settle a decision, Claude writes it as an ADR with `status: proposed`; you change it to `accepted` when you agree. Accepted ADRs aren't contradicted later: a new ADR supersedes them.
5. **Get a review** (with the reviewer). Open a draft pull request, then `/specbaton-reviewer:code <change>`: the reviewer writes `review.md`, a Claude subagent adds a pass as the team's reviewer, Claude adds a triage, and you decide each finding. After the fixes, `/specbaton-reviewer:code <change> validate` checks each one until the review closes.
6. **Close the session.** Say goodbye ("that's all for today", "hasta mañana"…) or run `/specbaton:handoff`. Claude writes the status, the ADRs, the indexes and the tasks, and proposes the commit of the memory.
7. **Next day.** Open a new session: it resumes from the files, not from a summary of the chat.

Two habits make it work:

- **One change per session.** To switch topics, run `/specbaton:handoff`, then `/clear`.
- **Teach the reviewer.** When the team comments on the pull request, `/specbaton-reviewer:code <change> learn` finds what humans caught that the agent missed and proposes improvements to the review skill.

With delegated implementation on, the session's model is kept for the thinking work:

| Work | Who |
| --- | --- |
| Explore, propose, check the plan | The session |
| Implement the tasks of `tasks.md` | The implementer, a subagent on `implement.model` (`sonnet` by default) |
| Check each unit: its diff, its verification and the spec | The session |
| An implementation defect | Back to the implementer, up to `max_retries` rounds (2 by default); then the session fixes it |
| A problem in the spec | The run stops; you decide, with a proposed ADR |
| The reviewer's findings, of the plan and the code | The session |

## Commands

| Command | When | What it does |
| --- | --- | --- |
| `/specbaton:setup` | Once per project, and again after an update | Detects the structure, creates the memory layer and `.claude/specbaton.json`. In a project already set up, offers only what's missing or new |
| `/specbaton:resume-work [change]` | A hook asks for it at the start of every session; also by hand | Offers to commit what an earlier handoff left uncommitted, reads `NOW.md`, the change's status and its ADRs, checks git since the last handoff, and summarizes |
| `/specbaton:handoff [change]` | When you say goodbye (a hook asks for it), when the context gets heavy, or before switching changes | Writes the status, creates the missing ADRs as `proposed`, updates the indexes, tasks and code graphs, and proposes the commit |
| `/specbaton:implement [change] [mode] [model] [range]` | When Claude offers it, once a change's tasks are ready; also by hand | A subagent on a cheaper model implements each unit of `tasks.md`; the session checks each one (its diff, its verification and the spec) before checking it off |
| `/specbaton-reviewer:setup` | Once per project | Chooses the reviewer CLI and models, creates the review skill, runs three real read-only tests |
| `/specbaton-reviewer:plan <change>` | Right after proposing a change | The reviewer writes `plan.md`; Claude sends back only verifiable gaps, up to 3 rounds in the same conversation |
| `/specbaton-reviewer:code <change>` | Right after opening a draft pull request | The reviewer reviews the diff and, in parallel, a Claude subagent reviews as the team's reviewer; Claude adds a triage where you decide each finding |
| `/specbaton-reviewer:code <change> validate` | After the fixes | The reviewer validates each fix in the same conversation, until the review closes |
| `/specbaton-reviewer:code <change> learn` | When the team comments on the pull request | Classifies what humans found that both passes missed, turns it into lessons, and proposes improvements to the review skill when a pattern repeats |

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
| **W**, workspace | A folder with several repos | The root becomes a private git repo whose `.gitignore` allows only the memory files; the team repos stay untouched |
| **A**, in the repo | Your own repo, or one whose team adopts the memory | The memory lives in the repo |
| **B**, beside the repo | A team repo you don't want to change | The memory lives in a private repo beside it; the rules go in `CLAUDE.local.md`, kept out of git, and each change's status in `<memory>/status/` |

The setup never adds a remote to a memory repo: it may hold your company's content, so where it's pushed is your call.

Rules for ADRs: the rejected alternatives are required (they're what a summary drops), an accepted ADR is never contradicted (a new one supersedes it), and an accepted ADR's body is never edited.

### Code graphs (optional)

With [graphify](https://pypi.org/project/graphifyy/), each *unit* (a repo, a service or a package) gets a graph under `graphify-out/units/`, so Claude asks about the code's structure instead of reading it file by file. Besides each unit's graph there's a platform graph for questions that cross units: the units' graphs merged (`merge`, the default for several repos) or one graph of the whole root (`full`, the default for a monorepo, which keeps the real imports between units).

Units are discovered on every run: repos in a multi-repo folder, or folders with a `package.json`, `pyproject.toml`, `go.mod`… in a monorepo. A folder you add later gets its graph the first time a session works in it, since `/specbaton:handoff` refreshes the graphs of the units a session touched. The setup shows what it found and lets you leave units out (`exclude`) or add folders it missed (`include`).

### Obsidian (optional)

Open the memory layer as an [Obsidian](https://obsidian.md) vault for a dashboard of ADRs and changes (it uses the Dataview plugin, which you install). The setup sets the folders Obsidian leaves out of its search and graph view: always `graphify-out/`, plus the code folders you choose. It can also color the graph view by path: ADRs, changes, specs, status and each folder of yours in its own color.

## The reviewer

| `cli` | Tool | How it stays read-only | Resumes with |
| --- | --- | --- | --- |
| `cursor` | Cursor (`cursor-agent`) | `--mode=ask`, never `--force` | `--resume=<id>` |
| `agy` | Antigravity (`agy`) | Session-only `--settings` with deny rules for commands, writes, MCP and URLs | `--conversation <id>` |
| `claude` | Claude Code with another model | `--tools "Read,Grep,Glob"`, no MCP tools, no user or project settings (so no hooks or plugins) | `--resume <id>` |
| `custom` | Any CLI | Its own read-only mode | When it supports it; otherwise each round carries the previous output |

Whatever the CLI, the real guarantee is the wrapper's: a git snapshot of the root, every nested repo and an external memory layer before and after the run, plus a search for files changed during it. If anything changed, it stops with exit code 4 and reverts nothing.

A reviewer from another model family brings other blind spots. Claude reviewing Claude works, and still brings a session with no memory of how the code was written, but it shares more of them: pick at least a different model, and remember it spends from the same account.

**The reviewer pass.** The reviewer agent reviews against the author's own account (proposal, specs, design and ADRs), so a case the spec misses, the review misses too, and most reviewer CLIs can't run code. So round 1 of `/specbaton-reviewer:code` adds a pass as the team's reviewer: a Claude subagent (`pass_model`, `sonnet` by default) with a clean context that reads only what the team sees (the diff, the pull request's text, the ticket and the RFC, when there are ones) and the code, never the specs, the ADRs or the other review. It lists candidate failure paths first, verifies each by reading the code or running the library in a scratch folder, and blocks by what ships if the pull request merges as it is. Its findings join the triage marked `T`, next to the agent's `A`. What both passes miss becomes a lesson in the review skill's `references/lessons.md`, which the pass applies next time.

The plan and the reviews live in the change's OpenSpec folder, so the reviewer works with OpenSpec changes.

**Privacy.** The memory plugin sends nothing anywhere: its hooks only add text to the session, the code graphs are built locally, without a model, and the implementer is a subagent of your own Claude Code session. The reviewer is the exception: the diff, the specs and the files it reads go to the CLI you choose, under your own account with that tool. The wrapper masks the usual secrets in the diff (`.env`-style keys, PEM keys, known token prefixes), but check what you send. The learning step reads the pull request's comments with `gh`.

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
  "implement": {"enabled": true, "model": "sonnet", "effort": "", "mode": "group", "max_retries": 2},
  "farewell_patterns": [],
  "reviewer": {
    "cli": "agy",
    "plan_model": "…",
    "review_model": "…",
    "base": "origin/main",
    "skill": "acme-code-review",
    "pass_model": "sonnet",
    "exclude": [".obsidian"],
    "max_rounds": 3
  }
}
```

`farewell_patterns` adds goodbyes in other languages (regular expressions) to the built-in English and Spanish ones. `implement` sets delegated implementation: the implementer's `model` (`sonnet`, `opus`, `haiku`, `fable`, or `inherit` for the session's), its `effort` (empty for the model's own), the `mode` (`task`, `group` or `change`) and `max_retries`, the rounds a unit goes back to the implementer before the session fixes it. A feature set to `false` (`{"enabled": false}` for `implement`) was turned down, and a later setup doesn't ask about it again.

## Updating and uninstalling

Plugins from this marketplace don't update on their own unless you turn on auto-update for it (`/plugin`, **Marketplaces** tab). To update by hand:

```bash
claude plugin update specbaton@specbaton
claude plugin update specbaton-reviewer@specbaton
```

Then start a new session (or run `/reload-plugins`) and run `/specbaton:setup` again: it keeps what's there and offers only what's new. `claude plugin marketplace update specbaton` alone only refreshes the listing.

To uninstall, `claude plugin uninstall specbaton@specbaton`. Your memory files, the rules and `.claude/specbaton.json` stay: they're yours. Without the plugin, the rules' references to its commands simply go unused.

## Troubleshooting

- **A session doesn't open with a summary.** The hooks stay silent when there's no `.claude/specbaton.json` at or above the folder you opened, or when `python3` is missing. Run `/specbaton:resume-work` by hand, or `/specbaton:setup` if the project isn't set up.
- **The handoff doesn't run when you say goodbye.** Short goodbyes ("bye", "good night", "chao") count only at the start or end of a message, so "the goodbye screen has a bug" isn't one. Run `/specbaton:handoff`, or add your own phrases in `farewell_patterns`.
- **`/specbaton:implement` keeps asking for permission.** Accept-edits mode approves file edits only: the implementer's test commands, and the session's own verification runs, still ask. For an unattended run, allow the project's test commands (and `git diff`) in `/permissions` or the project's `.claude/settings.json`, or use auto mode (Shift+Tab cycles the modes).
- **The reviewer stops with exit code 3** (the CLI isn't installed, signed in or trusting the folder), **4** (the agent changed files: nothing is reverted, and Claude shows what changed) **or 5** (another failure, with its log). The commands say which, and offer to go on without the reviewer when it can't run.

## Development

Version 0.5.1 (memory) and 0.2.1 (reviewer), early. See [CHANGELOG.md](CHANGELOG.md).

- `bash tests/hooks.test.sh` checks the memory plugin's hooks and settings with simulated hook inputs.
- `bash tests/setup.test.sh` checks how a second setup finds what's in place, what's missing and what's new.
- `bash tests/graphs.test.sh` checks how units are discovered for the code graphs, and builds real graphs when graphify is installed.
- `bash tests/implement.test.sh` checks how `tasks.py` splits a change's tasks into units, the working-tree snapshots of `snapshot.sh` (a same-size edit in the same second included), and that the implementer's prompt and every skill's scripts line up.
- `bash tests/reviewer.test.sh` checks the wrapper with fake CLIs for the four adapters: answers, resume flags, denied actions, writes inside repos and inside ignored folders, unknown models, usage limits and secret masking.
- `claude plugin validate .` checks the marketplace and each plugin's manifest.
- The read-only behavior of each real CLI was checked by hand in November 2026, against Cursor's CLI, Antigravity 1.5.1 and Claude Code 2.1.

Issues and pull requests are welcome. Run the tests before opening one.

## License

MIT. See [LICENSE](LICENSE).
