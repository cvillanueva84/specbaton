---
name: resume-work
description: Resume the work in a clean session from the memory files (NOW.md, the change's status, the ADRs and git), not from the chat. Run it when a specbaton hook asks for it at the start of a session, when the user types /specbaton:resume-work, or when they ask to pick up where they left off.
argument-hint: "[change]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" *)
---
Resume the work from the files, not from memory. Change or epic: $ARGUMENTS (when empty, use NOW.md; when it lists more than one active change, ask the user which).

First, get this project's settings: `python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" "${CLAUDE_PROJECT_DIR}"`. In what follows, MEM is its `memory_dir_abs`, STATUS is its `status_path_abs` with `{change}` replaced by the change's name, and `openspec` says whether the project uses OpenSpec. If it exits with 1, specbaton isn't set up in this project: say so in one line, suggest `/specbaton:setup`, and stop.

0. **Pending commit.** Run `git -C <MEM> status --short`. If the memory layer has uncommitted changes from an earlier handoff, show them with a short summary and propose the commit before going on. Commit only with the user's approval.
1. **Read the state.** Read `<MEM>/NOW.md`, the epic document it links to (if any) and, when there's an active change, its STATUS file, plus `proposal.md`, `design.md` and `tasks.md` when the project uses OpenSpec and they exist.
2. **Decisions.** In `<MEM>/decisions/README.md`, find the `accepted` and `proposed` ADRs of the change's units, and open the ones that affect the next step.
3. **What changed.** Run `git log --since="<the status file's date>" --format="%h %an %s" -- <the change's paths>` in the matching repo (in a multi-repo workspace, `git -C <repo> log …` in each). Separate the user's commits from other people's.
   If the change has `review.md` or `review-<TICKET>.md` files (from specbaton-reviewer) whose pull request is still open, mention that `/specbaton-reviewer:code <change> learn` checks it for new comments from human reviewers.
4. **Summary.** Give a short summary: where we left off, the next step, blockers, the ADRs that apply, and what changed since the handoff that isn't in the state. Flag any commit by someone else that contradicts an ADR or the spec.
5. **Stale state.** If the state is out of date, propose the correction and mark with [UNCERTAIN] whatever you can't infer from the code.
6. **Wait.** Don't modify code until the user confirms. If their message is already a concrete instruction, that counts as confirmation.

Reply in the user's language.
