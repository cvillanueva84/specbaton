---
name: code
description: Second-opinion code review of a change with the reviewer agent (read-only), with validation rounds in the same conversation until the findings close, and a learning step that turns what human reviewers caught into improvements to the team's review skill. One review.md per change, or one review-<TICKET>.md per pull request. Run it when the user types /specbaton-reviewer:code, and right after the user confirms a draft pull request is open, without waiting to be asked.
argument-hint: "<change> [validate|learn] [ticket] [base] [model]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/change_diff.sh" *) Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/pr_human_comments.sh" *)
---
Ask the reviewer agent for a review of the change's implementation and, after the fixes, ask it to validate them **in the same conversation**, until the findings close. The agent only reads and returns text; you save the file, do the triage, and fix only what the user approves. Round 1 adds a pass as the team's reviewer: a subagent of yours with a clean context, which sees only what the team sees and can run the libraries.

Arguments: $ARGUMENTS. The first is the change (when empty, the active change in the memory layer's NOW.md). If the second is `validate`, this is a validation round (step B); if it's `learn`, it's the learning step (step C); otherwise it's a new review (step A). Then may come the pull request's ticket (an argument shaped like a ticket key, for example `ABC-123`), the diff's base (default: `base` in the settings) and the model (default: `review_model`).

Reply to the user in their language.

**Settings.** First run `python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" "${CLAUDE_PROJECT_DIR}"`. If it exits with 1, or prints no `cli`, the reviewer isn't set up: suggest `/specbaton-reviewer:setup` and stop. Note `cli`, `review_model`, `pass_model`, `base`, `skill`, `memory_dir_abs` (MEM), `status_path_abs` (STATUS, with `{change}` replaced), `memory_outside_root`, `custom_resume` and `max_rounds`.

**When.** Round 1 runs as soon as the user confirms they opened the pull request, without waiting to be asked. The pull request opens as a draft, and becomes ready when the review is `closed`.

**One review per pull request.** When the change has more than one pull request (STATUS lists several branches or tickets), the review is per ticket. If the user didn't give the ticket, ask which. The file is `openspec/changes/<change>/review-<TICKET>.md`, and below `review.md` means that file. With a single pull request, it's `review.md`.

**Running the wrapper** means, from the project root, in the background and with a 25-minute limit (the Bash tool stops foreground commands at 10):
`bash "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_readonly.sh" <prompt file> <output file> <model>`
Before waiting, show the user the "Live progress: tail -f …" line it prints. Its exit codes are handled as in `/specbaton-reviewer:plan`: with `3`, offer to do the review yourself (`generated_by: claude`, no rounds; the reviewer pass still runs); with `4`, stop and show what changed; with `5`, show the error and the log.

## The change's diff (used by A and B)

1. **Scope.** Take the change's repos from STATUS. If it isn't clear, ask. Run `git -C <repo> fetch origin` in each.
2. **Diff.** From the root, run `bash "${CLAUDE_SKILL_DIR}/../../scripts/change_diff.sh" <base> <repo> [<repo>...] > <temporary file>` (with `mktemp`, outside the workspace). In a monorepo or a single repo, the repo is `.`. In a per-ticket review, pass each repo as `<repo>@origin/<the pull request's branch>`: then the diff is only that pull request's, even if the repo is on another branch. The script masks secrets as `<redacted>`. Before sending the prompt, `grep` the file to check no key value is left in sight. If it's over 200 KB, tell the user its size per repo and ask whether to narrow the scope.
3. **`{{SCOPE}}`** (used by both prompts):
   - in a per-ticket review: "This review covers only the pull request of <TICKET> (<repo>@<branch>), with tasks <numbers> of `tasks.md`. What belongs to the change's other tickets (<tickets>) isn't a gap of this pull request.";
   - in a change with a single pull request: "It covers the whole change."

## A. New review (round 1)

1. If `review.md` already exists with `state: open`, ask the user whether to validate that one (step B) or start a new one. A new review replaces the old one (it stays in git).
2. Build the diff. Copy `${CLAUDE_SKILL_DIR}/../../prompts/review.md` to a temporary file, replacing `{{CHANGE}}`, `{{ROOT}}`, `{{MEM_DIR}}`, `{{LANGUAGE}}` (the user's language), `{{SCOPE}}`, `{{REVIEW_SKILL}}` (the content of `.claude/skills/<skill>/SKILL.md`; if it doesn't exist, stop and tell the user to run `/specbaton-reviewer:setup`), `{{DIFF}}` and `{{MEMORY_CONTEXT}}` (empty when `memory_outside_root` is false; otherwise the content of STATUS and of the ADRs that apply, each under a heading with its path). Run the wrapper.
3. **Reviewer pass.** While the wrapper runs, unless `pass_model` is `off`, run the pass as the team's reviewer:
   - **Its inputs,** in a new scratch folder (`mktemp -d`, outside the workspace), with no personal data:
     - `{{DIFF_PATH}}`: the same diff file;
     - `{{PR_TEXT_PATH}}`: the pull request's title and body as the team sees them (`gh pr view <number> -R <owner>/<repo> --json title,body`), or, before it's open, its draft in `<MEM>/pull-request/`;
     - `{{TICKET_PATH}}`: when a tracker is connected, the ticket and its parent story or epic (summary, description, acceptance criteria, and what the story leaves out); otherwise `none`;
     - `{{RFC_PATH}}`: the RFC or design document the team reviews against, when STATUS or the user names one; otherwise `none`.
   - **Lessons.** When `.claude/skills/<skill>/references/lessons.md` doesn't exist, create it from `${CLAUDE_SKILL_DIR}/../../templates/review-skill/references/lessons.md`, with `{{DATE}}` set to today, and tell the user.
   - **Prompt.** Copy `${CLAUDE_SKILL_DIR}/../../prompts/reviewer-pass.md` to a temporary file, replacing the four paths above, `{{REPO}}`, `{{PR}}`, `{{TICKET}}` (`none` without a tracker), `{{BRANCH}}`, `{{BASE}}`, `{{ROOT}}`, `{{SCRATCH}}` (another new scratch folder), `{{SKILL_DIR}}` (the absolute path of `.claude/skills/<skill>`) and `{{LANGUAGE}}`.
   - **Launch** a `general-purpose` subagent with `model: "<pass_model>"` and that prompt as its whole message. Don't give it your context, your conclusions or the agent's review: its value is that it doesn't know them.
   - **Read-only check.** Before launching it, save `git -C <repo> status --porcelain` for each of the change's repos, and compare it when the subagent returns. If anything changed, stop and show the user what changed; revert nothing.
4. Write `openspec/changes/<change>/review.md` with the frontmatter (below; `round: 1`, `state: open`), followed by the agent's output and, after it, the reviewer pass's output.
5. **Triage.** Add at the end `## Triage (Claude)`, with one row per finding of both passes. Its origin is `A` (the reviewer agent) or `T` (the team-reviewer pass); a finding both raised gets a single row, `A+T`:
   `| Origin | Finding | Claude's opinion | User's decision | Response |`
   - Opinion: **agree**, **disagree** (with the evidence in the code that refutes it) or **needs your decision**. Mark as an ADR proposal anything that will matter after the change.
   - Before giving an opinion, trace the trigger through today's flow. When the opinion depends on how a library behaves, run it from a scratch folder against the repo's installed copy, and cite the command. Not finding the trigger never dismisses a finding: lower it to non-blocking only when the system already prevents that state, and say what prevents it.
   - Before proposing a fix, check every caller and the layer that owns the rule.
   - Decision and Response stay empty.
   - Compare the tracker's ticket (scope and acceptance criteria) with the pull request's text, since the reviewer agent doesn't read it. Before saying an acceptance criterion is missing, read the parent story or epic and what it leaves out of this story. If they don't match, add a `*(Ticket.)*` row with the difference.
6. Show the user the verdict, the count per severity, the reviewer pass's blocking findings and your triage. **Fix nothing** until the user says what to handle. With their decisions, fill the "User's decision" column: fix, dismiss or postpone.

## Between rounds: fixes

Fix only what the user marked "fix". For each finding, fill the triage's **Response** column:
- **fixed:** commit or file, and what changed;
- **dismissed:** the evidence;
- **postponed:** by the user's decision.

That way the next round can run in another session: everything is in `review.md`.

## B. Validation (`/specbaton-reviewer:code <change> validate`)

1. Read `review.md`: `reviewer_chat`, `round`, `heads` and the triage table. If a finding has no Response, ask the user before going on.
2. Build the updated diff (same base) and the list of new commits since the previous round's `heads` (`git -C <repo> log --oneline <head>..HEAD`).
3. Copy `${CLAUDE_SKILL_DIR}/../../prompts/review-followup.md` to a temporary file, replacing `{{ROUND}}` (round + 1), `{{CHANGE}}`, `{{SCOPE}}`, `{{RESPONSES}}` (one line per finding of both passes, starting with its origin, with its response and its evidence), `{{NEW_COMMITS}}` and `{{DIFF}}`. `{{PREVIOUS_OUTPUT}}` stays empty, unless the CLI can't resume (`cli` is `custom` and `custom_resume` is false): then it's "## Your previous review" followed by the review's current text. Run the wrapper with `SPECBATON_RESUME=<reviewer_chat>` in front (only when the CLI can resume).
4. Replace the agent's part of `review.md` (between the frontmatter and `## Reviewer pass (Claude)`) with the output, which is the whole updated review. The reviewer pass runs only in round 1: keep its section as it is. Update `round`, `heads`, `verdict` and `date` in the frontmatter. Redo the triage only for the findings marked **not resolved**, **insist** or **new**, keeping the closed rows.
5. **Closing.**
   - When the verdict is `pass`, or no open findings remain except postponed ones, set `state: closed`.
   - When round `max_rounds` (3 by default) is reached with open findings, or the agent insists on something you refuted twice, **stop iterating**: set `state: needs-decision` and show the user the disagreements with each side's evidence. The user decides.
6. Show the user the verdict, what closed in this round and what's still open. End with how to open the conversation with the reviewer agent, as in `/specbaton-reviewer:plan`.

## C. Learning (`/specbaton-reviewer:code <change> learn [ticket]`)

Compares what the human reviewers found on the pull request with what the reviewer agent and the reviewer pass found, and turns what they missed into lessons and, when the pattern repeats, into improvements to the team's review skill (`.claude/skills/<skill>/`).

**When:** as soon as the pull request gets comments from human reviewers. `/specbaton:resume-work` suggests it, and the user can ask for it. It can run again on the same pull request: each run processes only what's new.

1. Read `review.md`: the pull request and the repo (`ticket`, `heads`), every finding with its state, the triage and `learned_until`, when it exists.
2. Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/pr_human_comments.sh" <repo> <pull request> [<learned_until>]` into a temporary file. If there are no new comments, say so and stop. Read each thread whole, since replies refine the original comment, and don't count what the reviewer withdrew.
3. Classify each human finding, one per root cause even when it spans several comments:
   - **`caught`:** the reviewer agent or the reviewer pass found it, and it was handled. Cite the finding and which pass it came from (`A`, `T` or `A+T`).
   - **`caught-dismissed`:** one of the passes found it and the triage dismissed it. The gap was ours, not the skill's: tell the user separately.
   - **`missed-covered`:** no pass caught it, but a pass of the skill or a lesson covers it.
   - **`missed-uncovered`:** neither the passes nor the lessons cover it.
   - **`out-of-scope`:** a style or readability preference, a product decision, or something outside the pull request and its ticket. It's recorded, and when it was already seen in another pull request, it becomes a lesson.
4. **Evidence.**
   - In `.claude/skills/<skill>/references/evidence/pr-feedback-<YYYY-MM>.md` (the pull request's month), add a section per pull request with one row per finding: the pointer (`repo#PR / id`), the pass, the class and the finding in one line. No reviewer names, personal data or key values.
   - In the `## Validation results` table of `SOURCES.md`, add a row with each class's count and the rate (`caught` over `caught` plus `missed-*`, counting what either pass caught), and add a line to the changelog.
5. **Lessons and skill.** Propose the changes, without applying them yet:
   - **For each `missed-*`, and each `out-of-scope` already seen in another pull request,** a lesson in `.claude/skills/<skill>/references/lessons.md` (create it from the template, as in step A, when it doesn't exist): rule · scope · evidence · last confirmed. When the lesson already exists, propose updating its evidence and date, and tell the user the rule existed and wasn't applied.
   - **`SKILL.md` changes only when** the pattern shows up in two or more pull requests, it's High, or a pass gave false positives twice. Prefer sharpening a pass's question or adding an example, and create a new pass only when none covers it.
   - **When the pattern depends on something neither pass can read or run** (code loaded at runtime, production data), it goes to "Known limitations" in `SPEC.md`.
   - **`SKILL.md` goes whole into the agent's prompt,** so it stays free of references (the lessons included) and under 12 KB.

   Show the user the proposed diff. With their OK, apply it, and when `SKILL.md` changed, validate it: frontmatter with `name` and `description`, and under 12 KB (`wc -c`).
6. In the review's frontmatter, set `learned_until` to the date on the script's `last:` line.
7. Show the user the counts, the triage dismissals that turned out real, and the lessons and changes to the skill, applied or pending.

## `review.md` frontmatter

```
---
type: review
change: <change>
ticket: <TICKET and #PR, only in a per-ticket review>
generated_by: <the CLI's --version output> · model <model>; reviewer pass: claude <pass_model>
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
