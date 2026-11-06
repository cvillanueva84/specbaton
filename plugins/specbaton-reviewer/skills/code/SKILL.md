---
name: code
description: Second-opinion code review of a change with the reviewer agent (read-only), with validation rounds in the same conversation until the findings close, and a learning step that turns what human reviewers caught into improvements to the team's review skill. One review.md per change, or one review-<TICKET>.md per pull request. Run it when the user types /specbaton-reviewer:code, and right after the user confirms a draft pull request is open, without waiting to be asked.
argument-hint: "<change> [validate|learn] [ticket] [base] [model]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/change_diff.sh" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/pr_human_comments.sh" *)
---
Ask the reviewer agent for a review of the change's implementation and, after the fixes, ask it to validate them **in the same conversation**, until the findings close. The agent only reads and returns text; you save the file, do the triage, and fix only what the user approves.

Arguments: $ARGUMENTS. The first is the change (when empty, the active change in the memory layer's NOW.md). If the second is `validate`, this is a validation round (step B); if it's `learn`, it's the learning step (step C); otherwise it's a new review (step A). Then may come the pull request's ticket (an argument shaped like a ticket key, for example `ABC-123`), the diff's base (default: `base` in the settings) and the model (default: `review_model`).

Reply to the user in their language.

**Settings.** First run `python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" "${CLAUDE_PROJECT_DIR}"`. If it exits with 1, or prints no `cli`, the reviewer isn't set up: suggest `/specbaton-reviewer:setup` and stop. Note `cli`, `review_model`, `base`, `skill`, `memory_dir_abs` (MEM), `status_path_abs` (STATUS, with `{change}` replaced), `memory_outside_root`, `custom_resume` and `max_rounds`.

**When.** Round 1 runs as soon as the user confirms they opened the pull request, without waiting to be asked. The pull request opens as a draft, and becomes ready when the review is `closed`.

**One review per pull request.** When the change has more than one pull request (STATUS lists several branches or tickets), the review is per ticket. If the user didn't give the ticket, ask which. The file is `openspec/changes/<change>/review-<TICKET>.md`, and below `review.md` means that file. With a single pull request, it's `review.md`.

**Running the wrapper** means, from the project root, in the background and with a 25-minute limit (the Bash tool stops foreground commands at 10):
`bash "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_readonly.sh" <prompt file> <output file> <model>`
Before waiting, show the user the "Live progress: tail -f …" line it prints. Its exit codes are handled as in `/specbaton-reviewer:plan`: with `3`, offer to do the review yourself (`generated_by: claude`, no rounds); with `4`, stop and show what changed; with `5`, show the error and the log.

## The change's diff (used by A and B)

1. **Scope.** Take the change's repos from STATUS. If it isn't clear, ask. Run `git -C <repo> fetch origin` in each.
2. **Diff.** From the root, run `bash "${CLAUDE_SKILL_DIR}/../../scripts/change_diff.sh" <base> <repo> [<repo>...] > <temporary file>` (with `mktemp`, outside the workspace). In a monorepo or a single repo, the repo is `.`. In a per-ticket review, pass each repo as `<repo>@origin/<the pull request's branch>`: then the diff is only that pull request's, even if the repo is on another branch. The script masks secrets as `<redacted>`. Before sending the prompt, `grep` the file to check no key value is left in sight. If it's over 200 KB, tell the user its size per repo and ask whether to narrow the scope.
3. **`{{SCOPE}}`** (used by both prompts):
   - in a per-ticket review: "This review covers only the pull request of <TICKET> (<repo>@<branch>), with tasks <numbers> of `tasks.md`. What belongs to the change's other tickets (<tickets>) isn't a gap of this pull request.";
   - in a change with a single pull request: "It covers the whole change."

## A. New review (round 1)

1. If `review.md` already exists with `state: open`, ask the user whether to validate that one (step B) or start a new one. A new review replaces the old one (it stays in git).
2. Build the diff. Copy `${CLAUDE_SKILL_DIR}/../../prompts/review.md` to a temporary file, replacing `{{CHANGE}}`, `{{ROOT}}`, `{{MEM_DIR}}`, `{{LANGUAGE}}` (the user's language), `{{SCOPE}}`, `{{REVIEW_SKILL}}` (the content of `.claude/skills/<skill>/SKILL.md`; if it doesn't exist, stop and tell the user to run `/specbaton-reviewer:setup`), `{{DIFF}}` and `{{MEMORY_CONTEXT}}` (empty when `memory_outside_root` is false; otherwise the content of STATUS and of the ADRs that apply, each under a heading with its path). Run the wrapper.
3. Write `openspec/changes/<change>/review.md` with the frontmatter (below; `round: 1`, `state: open`) followed by the agent's output.
4. **Triage.** Add at the end `## Triage (Claude)`, with one row per finding:
   `| Finding | Claude's opinion | User's decision | Response |`
   - Opinion: **agree**, **disagree** (with the evidence in the code that refutes it) or **needs your decision**. Mark as an ADR proposal anything that will matter after the change.
   - Decision and Response stay empty.
   - Compare the tracker's ticket (scope and acceptance criteria) with the pull request's text, since the reviewer agent doesn't read it. If they don't match, add a `*(Ticket.)*` row with the difference.
5. Show the user the verdict, the count per severity and your triage. **Fix nothing** until the user says what to handle. With their decisions, fill the "User's decision" column: fix, dismiss or postpone.

## Between rounds: fixes

Fix only what the user marked "fix". For each finding, fill the triage's **Response** column:
- **fixed:** commit or file, and what changed;
- **dismissed:** the evidence;
- **postponed:** by the user's decision.

That way the next round can run in another session: everything is in `review.md`.

## B. Validation (`/specbaton-reviewer:code <change> validate`)

1. Read `review.md`: `reviewer_chat`, `round`, `heads` and the triage table. If a finding has no Response, ask the user before going on.
2. Build the updated diff (same base) and the list of new commits since the previous round's `heads` (`git -C <repo> log --oneline <head>..HEAD`).
3. Copy `${CLAUDE_SKILL_DIR}/../../prompts/review-followup.md` to a temporary file, replacing `{{ROUND}}` (round + 1), `{{CHANGE}}`, `{{SCOPE}}`, `{{RESPONSES}}` (one line per finding, with its response and its evidence), `{{NEW_COMMITS}}` and `{{DIFF}}`. `{{PREVIOUS_OUTPUT}}` stays empty, unless the CLI can't resume (`cli` is `custom` and `custom_resume` is false): then it's "## Your previous review" followed by the review's current text. Run the wrapper with `SPECBATON_RESUME=<reviewer_chat>` in front (only when the CLI can resume).
4. Replace the content of `review.md` (below the frontmatter) with the output, which is the whole updated review. Update `round`, `heads`, `verdict` and `date` in the frontmatter. Redo the triage only for the findings marked **not resolved**, **insist** or **new**, keeping the closed rows.
5. **Closing.**
   - When the verdict is `pass`, or no open findings remain except postponed ones, set `state: closed`.
   - When round `max_rounds` (3 by default) is reached with open findings, or the agent insists on something you refuted twice, **stop iterating**: set `state: needs-decision` and show the user the disagreements with each side's evidence. The user decides.
6. Show the user the verdict, what closed in this round and what's still open. End with how to open the conversation with the reviewer agent, as in `/specbaton-reviewer:plan`.

## C. Learning (`/specbaton-reviewer:code <change> learn [ticket]`)

Compares what the human reviewers found on the pull request with what the agent found, and turns what it missed into improvements to the team's review skill (`.claude/skills/<skill>/`).

**When:** as soon as the pull request gets comments from human reviewers. `/specbaton:resume-work` suggests it, and the user can ask for it. It can run again on the same pull request: each run processes only what's new.

1. Read `review.md`: the pull request and the repo (`ticket`, `heads`), every finding with its state, the triage and `learned_until`, when it exists.
2. Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/pr_human_comments.sh" <repo> <pull request> [<learned_until>]` into a temporary file. If there are no new comments, say so and stop. Read each thread whole, since replies refine the original comment, and don't count what the reviewer withdrew.
3. Classify each human finding, one per root cause even when it spans several comments:
   - **`caught`:** the agent found it and it was handled. Cite its finding.
   - **`caught-dismissed`:** the agent found it and the triage dismissed it. The gap was ours, not the skill's: tell the user separately.
   - **`missed-covered`:** no pass caught it, but one covers it. Its question needs sharpening, or an example.
   - **`missed-uncovered`:** no pass covers it.
   - **`out-of-scope`:** a style or readability preference, a product decision, a test plan step, or something outside the diff. It's recorded, but doesn't change the skill unless it repeats in another pull request.
4. **Evidence.**
   - In `.claude/skills/<skill>/references/evidence/pr-feedback-<YYYY-MM>.md` (the pull request's month), add a section per pull request with one row per finding: the pointer (`repo#PR / id`), the pass, the class and the finding in one line. No reviewer names, personal data or key values.
   - In the `## Validation results` table of `SOURCES.md`, add a row with each class's count and the rate (`caught` over `caught` plus `missed-*`), and add a line to the changelog.
5. **Proposal for the skill.** For each `missed-*`, propose a change, without applying it yet:
   - prefer sharpening a pass's question or adding an example to creating a pass;
   - create a new pass only when the pattern shows up in two or more pull requests, or it's High;
   - when the pattern depends on something the agent can't read (code loaded at runtime, production data), it goes to "Known limitations" in `SPEC.md`, not to a pass;
   - `SKILL.md` goes whole into the agent's prompt, so it stays free of references and under 12 KB.

   Show the user the proposed diff. With their OK, apply it and validate the skill: frontmatter with `name` and `description`, and under 12 KB (`wc -c`).
6. In the review's frontmatter, set `learned_until` to the date on the script's `last:` line.
7. Show the user the counts, the triage dismissals that turned out real, and the changes to the skill, applied or pending.

## `review.md` frontmatter

```
---
type: review
change: <change>
ticket: <TICKET and #PR, only in a per-ticket review>
generated_by: <the CLI's --version output> · model <model>
date: <YYYY-MM-DD>
base: <base, or <repo>@<base>, … when it differs per repo>
heads: <repo>@<short sha>, …
reviewer_chat: <conversation_id of round 1>
round: <n>
verdict: <pass | pass_with_risks | fail, as the agent gave it in the last round>
state: <open | closed | needs-decision>
learned_until: <ISO date of the last human comment processed; only after step C>
---
```
