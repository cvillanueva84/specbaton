# Lessons

Concrete rules from what the pre-review let through. The reviewer pass of `/specbaton-reviewer:code` applies every lesson whose scope matches the repo; `SKILL.md` doesn't reference this file, so it stays self-contained inside the reviewer agent's prompt.

`/specbaton-reviewer:code <change> learn` adds a lesson for each `missed-*` finding, and for each `out-of-scope` one already seen in another PR. When a lesson already exists, it updates its evidence and date instead, and says the rule existed and wasn't applied.

Format: **rule** · scope · evidence · last confirmed. Evidence is a pointer (`repo#PR / comment id`) or `seed`. No reviewer names, personal data or key values.

## Seeds

- **A defect on the PR's new path blocks, even when sibling code shares it or no real trigger is confirmed.** Tracing the trigger verifies that the path exists and never dismisses the finding. It's non-blocking hardening only when the system already prevents that state, and the finding says what prevents it. · all repos · seed · {{DATE}}
- **Check every exception path of every new external call against the ticket's failure lines.** A library that validates synchronously throws before any callback or promise, and a required field read from an optional field can be missing. · all repos · seed · {{DATE}}
- **A number without a recorded reason or measurement blocks.** Its basis goes in the PR text, the ticket or the RFC. A spec or a comment that only restates the number doesn't count, and neither does an ADR reviewers don't see. · all repos · seed · {{DATE}}
- **Before saying an acceptance criterion isn't met, read the parent story or epic and what it leaves out of this story.** · all repos · seed · {{DATE}}
- **Before suggesting a fix, check every caller and the layer that owns the rule.** · all repos · seed · {{DATE}}
- **Trace each step of the PR's test plan, deploy, rollout or rollback to the code path it triggers, and check it works as written.** · all repos · seed · {{DATE}}
- **When the PR says a path doesn't change, list every changed file that path imports,** shared texts and constants and global error reporters included. · all repos · seed · {{DATE}}

## Learned
