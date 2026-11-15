---
name: implement
description: Implement a change's tasks with a subagent on the model chosen in the settings (Sonnet by default), unit by unit, while this session checks each unit with evidence (its diff, its verification and the spec) before checking it off, so the session's costlier model is kept for the thinking work. Run it when the user types /specbaton:implement, says yes to the offer the project's rules make once a change's tasks are ready, or asks to implement a change in their own words.
argument-hint: "[change] [task|group|change] [model] [range]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" *) Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/tasks.py" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/snapshot.sh" *)
---
Implement a change's tasks through a subagent, unit by unit. The subagent writes the code; you coordinate, check each unit with evidence and decide what's next. Your checks are what make this cheaper than implementing here: they read the unit's diff and run its verification, and never redo the subagent's work.

Arguments: $ARGUMENTS. The change is the argument that isn't one of the others (when there's none, the active change in the memory layer's `NOW.md`; when that lists several or none, ask). `task`, `group` or `change` is the mode. `sonnet`, `opus`, `haiku`, `fable` or `inherit` is the model. A range of tasks looks like `1-3`, `2.1-2.4` or `1.2,3`. Arguments win over the settings for this run only.

Reply to the user in their language.

## 0. Settings

Run `python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" "${CLAUDE_PROJECT_DIR}"`. Note `root`, `memory_dir_abs` (MEM), `status_path_abs` (STATUS, with `{change}` replaced), `rules_file_abs`, `openspec`, `implement_enabled`, `implement_model`, `implement_effort`, `implement_mode` and `implement_max_retries`.

- Exit 1: specbaton isn't set up here. Suggest `/specbaton:setup` and stop.
- `implement_enabled` is false, or `openspec` is false: say in one line that delegated implementation is off in this project (it needs OpenSpec), suggest `/specbaton:setup` to turn it on, and stop.

## 1. Units

Run `python3 "${CLAUDE_SKILL_DIR}/../../scripts/tasks.py" openspec/changes/<change>/tasks.md --mode <mode> [--range <range>]`. It prints JSON: the change's `total`, `done` and `pending` counts, and the pending `units`, each with its tasks (`id`, `line`, `text`). With no units left, say so and suggest archiving the change, as `/opsx:apply` does. Otherwise tell the user in one line: the change, the mode, the number of units and the model.

## 2. Context

Build `{{CONTEXT_FILES}}` as a list of paths, not contents. The subagent reads them itself.

- With the `openspec` CLI installed, run `openspec instructions apply --change "<change>" --json`. Its `contextFiles` are the change's files; its `context`, when present, goes into `{{OPENSPEC_CONTEXT}}`. If its `state` is `blocked` (an artifact is missing), say which and stop.
- Without the CLI, the change's files are `proposal.md`, `specs/`, `design.md` and `tasks.md` under `openspec/changes/<change>/`, and `{{OPENSPEC_CONTEXT}}` is `none`.
- Add `plan.md` when it exists. If its frontmatter says `state: outdated`, tell the user and ask whether to go on with it before anything else.
- Add the `accepted` ADRs of the change's units, from `<MEM>/decisions/README.md`, and `<MEM>/docs/reference/gates.md` when it exists.

`{{REPOS}}` is each repo the change touches, from the `Unit | Repo/path` table in STATUS (`.` in a monorepo or a single repo; when STATUS doesn't say, ask). `{{RULES_FILE}}` is `rules_file_abs`. `{{ROOT}}` is `root`. `{{CHANGE}}` is the change's name.

## 3. Branches

Never switch branches. When STATUS maps the change's tasks to several tickets and branches, implement only the tasks of the ticket whose branch is checked out (narrow the range to them), and say which tasks remain for the other branches.

## 4. Each unit, in order

1. **Snapshot.** For each repo in `{{REPOS}}`, from the root: `bash "${CLAUDE_SKILL_DIR}/../../scripts/snapshot.sh" <repo>`. Keep each line: the tree before the unit, and HEAD.
2. **Launch.** Fill the prompt in "The implementer's prompt" below, the text inside its fence. `{{UNIT}}` is the unit's tasks, each task's `text` exactly as `tasks.py` printed it. Launch a `general-purpose` subagent with the Agent tool, with that filled text as its whole prompt, `model` set to the model (left out for `inherit`), and `effort` set only when the settings or the arguments set one. Give it none of your own context or conclusions. Tell the user which unit is running, in one line. Wait for its notification before doing anything else in the change's repos, and never assume its result.
3. **Report.** The subagent answers `done`, `blocked: spec` or `blocked: environment`, with the files it changed, the verification it ran and its doubts.
4. **Check.** Take a new snapshot of each repo. Your check is limited to:
   - **the unit's diff:** `git -C <repo> diff --stat <tree before> <tree now>`, then the diff itself, in each repo. Read nothing else of the code unless the diff points you to it;
   - **the verification, run by you:** each task's own verification (a "Verify:" line or similar, in any language) when it states one; otherwise the tests of the code the unit touched, with the commands in `gates.md` when it exists. The subagent's report of its run isn't evidence: your run is;
   - **the spec:** the scenarios the tasks name or, when they name none, the scenarios of the spec whose capability the touched code implements, and the design decisions and ADRs the tasks cite;
   - **the scope:** a change outside the unit's tasks is a defect.

   If HEAD moved or the branch changed in any repo, stop and show the user what happened. Revert nothing.
5. **Outcome.**
   - **Pass:** check off the unit's tasks in `tasks.md` (`- [ ]` to `- [x]` on each task's `line`) and go on to the next unit.
   - **Defect:** send the evidence (the scenario or task, the file and line, the failing output) to the same subagent with `SendMessage`, which keeps its context (load `SendMessage` with ToolSearch when it's deferred). Check its answer the same way. After `implement_max_retries` rounds that still fail, fix the unit yourself, with the smallest change, run its verification, check it off and note it for the summary.
   - **Spec problem**, reported by the subagent or found by your check: stop the run and show the user the evidence. Propose an ADR (`status: proposed`) and the change to the spec, the design or the tasks, as the project's rules say. Run nothing else until the user decides. When the subagent only misread the spec, it's not a spec problem: answer it with `SendMessage`.
   - **Environment problem** (a missing dependency, a service that isn't running, tests that already failed before the unit): stop and show it.

## 5. End

1. Run the local gate when `gates.md` exists: its commands, from each touched unit's folder.
2. Sum up for the user: the units done, the rounds each took, what you fixed yourself, the ADRs proposed and the gate's result.
3. Offer the next step the project's rules allow: a commit (with the user's approval, unless the rules say otherwise for that repo), and the pull request text when the ticket cycle rules are on. The implementer never commits; you commit only as those rules say.

The reviewer's findings, later, are fixed in this session, not by the implementer.

## 6. Heavy context

If your context gets heavy mid-run, finish the current unit and run `/specbaton:handoff`. The next session goes on with `/specbaton:implement <change>`, which starts from the first unchecked task.

## The implementer's prompt

It lives here, not in a file of its own: the plugin's other folders can sit outside what the session may read.

````markdown
# Implementer: one unit of a change's tasks

You implement part of a change whose proposal, specs and design are already settled. Another session coordinates the work: it chose these tasks for you, and when you answer it checks your work against the spec, runs the verification itself and decides what's next. Your job is to implement these tasks well, inside their scope, and to report exactly what you did.

- **Change:** `{{CHANGE}}`
- **Workspace root:** `{{ROOT}}`
- **Repos this change touches:** {{REPOS}}
- **Project rules:** `{{RULES_FILE}}`

## Read first

1. The project rules, `{{RULES_FILE}}`, read it yourself even if it seems already loaded. Follow them: they say, for example, whether a test comes first, and how the repo's code is written.
2. The change's files:

{{CONTEXT_FILES}}

3. The project context from OpenSpec (`none` when there isn't one):

{{OPENSPEC_CONTEXT}}

Before editing a unit of code, read its own instructions (README, `AGENTS.md`) and follow its style, its public APIs and its test setup.

## Your tasks

{{UNIT}}

## Rules

- Implement only the tasks above. Other tasks of `tasks.md` belong to other units, and changes outside these tasks are a defect, even when they look like improvements.
- Don't check off `tasks.md`: the coordinating session does it once it has checked your work.
- Don't edit the change's files (proposal, specs, design, tasks, plan), the ADRs or the memory files (`NOW.md`, status files, `decisions/`).
- Never commit, push, switch branches, stash, reset or rewrite history. Leave your changes in the working tree.
- Run each task's verification: the commands or tests the task states, or else the tests of the code you touched. Read their output: a test you didn't see pass isn't passing.
- When the spec seems wrong, incomplete or impossible to meet, or it contradicts the design or an ADR, don't work around it and don't choose for the user. Stop and answer `blocked: spec`, with the evidence: the scenario or decision, and what in the code or the task conflicts with it.
- When the environment stops you (a missing dependency, a service that isn't running, tests that already failed before your change), stop and answer `blocked: environment`, with the command and its output.
- If the coordinating session sends you findings about your work, fix exactly those, run the verification again and answer in the same shape.

## Your answer

In English, in this shape and nothing else:

```
done | blocked: spec | blocked: environment

## Files changed
- <path>: <what changed, in one line>

## Verification
- `<command>`: <outcome, such as "12 passed" or the failing test and its message>

## Doubts
- <what you weren't sure about, or "none">
```

For a `blocked` answer, put the evidence under `## Doubts`, and list in `## Files changed` whatever you changed before stopping.
````
