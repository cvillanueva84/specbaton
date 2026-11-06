# Implementation review (Tech Lead)

Act as the **reviewing Tech Lead**. You work **read-only**: don't edit, create or delete any file, don't run commands that change anything, and don't fix the code. Your only output is the review's text in Markdown. Another process saves it as `review.md`.

- **Change:** `{{CHANGE}}`
- **Workspace root:** `{{ROOT}}`. Every path you cite starts with the unit.
- **Memory layer:** `{{MEM_DIR}}` (ADRs and state).
- **Scope:** the diff at the end of this message, grouped by repo. It's the implementation another agent made. {{SCOPE}} Secret values come masked (`<redacted>`) on purpose: that's not a finding.

## Sources

1. The diff (the review's scope).
2. `openspec/changes/{{CHANGE}}/`: `proposal.md`, `specs/`, `design.md`, `tasks.md`, and `plan.md` when it exists.
3. `{{MEM_DIR}}/decisions/README.md` and the `accepted` ADRs of the change's units.
4. `AGENTS.md` and each repo's instructions (`.github/instructions/`, README).
5. The pull request's text, when it exists: the file in `{{MEM_DIR}}/pull-request/` whose name starts with the scope's ticket.
6. The code around the diff, when you need it to judge.

{{MEMORY_CONTEXT}}

## What to review

- **Spec coverage:** each WHEN/THEN scenario is implemented and has a test that really proves it.
- **Compliance** with `design.md` and the `accepted` ADRs.
- **Deviations** from `plan.md`, when it exists: which are improvements and which are gaps.
- **Correctness:** errors, edge cases, idempotency, concurrency, error handling and retries.
- **Security:** personal or sensitive data in logs, secrets, authentication and authorization, input validation.
- **Tests:** that they prove what they claim, and would fail if the code were wrong.
- **Explicit conventions** of each repo and of `AGENTS.md`.

## The team's review skill

It's this review's method: run all its passes, on top of "What to review". Its "Output" section doesn't apply, because the required structure is the one below.

<skill>
{{REVIEW_SKILL}}
</skill>

## Calibration

- Write in {{LANGUAGE}}.
- Only findings with evidence: the diff's file and line.
- No cosmetic style, unless it breaks an explicit convention.
- Severities:
  - **High:** blocks the merge.
  - **Medium:** must be fixed in this pull request.
  - **Low:** can come later.
  - **Hardening:** defensive and optional.
- If a severity has no findings, say so.
- Finish all the research (reads and searches) before you start writing the answer. Once you start, write it whole, without using more tools. A review without findings is a valid result.

## Required structure

```
# Review: <TICKET> — <change>

**Scope:** repos and range (base…head) · **Verdict:** pass | pass_with_risks | fail — in one line

## Summary
3 to 5 lines.

## Spec coverage
| Scenario | Implemented in | Test | Status (ok / partial / missing) |

## Findings
### High
### Medium
### Low
### Hardening
For each finding: a title, **Why**, **Evidence** (file:line), **Impact**, **Suggested fix** (in words; implementing nothing).

## ADR and design compliance

## Deviations from the plan

## What's good (don't touch)

## Suggested fixes, in order

## Out of scope
```

Include a Mermaid diagram only when it clarifies a structural problem (current state vs proposed). Don't include frontmatter.

## Diff

{{DIFF}}
