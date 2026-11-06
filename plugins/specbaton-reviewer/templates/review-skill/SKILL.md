---
name: {{SKILL_NAME}}
description: Pre-review a change or PR in {{PROJECT}} the way the team's reviewers do, before they see it. Use for /specbaton-reviewer:code, "review this before I open the PR", "what will reviewers flag", or a second-opinion review of our own diff. Extends a generic code-review checklist with the checks reviewers keep raising - real library behavior instead of mocks, final vs retryable failures, rollout and rollback, hidden consumers, unjustified constants, and PR claims that the code doesn't back.
---

# {{SKILL_TITLE}}

Review the diff the way the team's reviewers do: open the libraries, list how each branch is reached in production, and check every claim the PR makes. Most review comments come from asking "what really happens when…?" and reading the dependency's source, not from style.

## Inputs

- The diff (the scope for findings) and the code around it.
- The ticket's acceptance criteria: the change's artifacts (proposal, specs, design, tasks) and the PR text, when they exist.
- The ADRs for the units involved.
- Installed dependencies, for library behavior ({{DEPS_LOCATION}}; the version comes from the lockfile). Open those files by path, because search tools may skip dependency folders.

## Rules

1. Evidence or nothing. Every finding cites file:line in the diff, and for library behavior, the library's file:line and version.
2. A scenario whose test mocks the dependency it relies on is **partial**, not ok, unless another test runs the real dependency with only the transport stubbed.
3. When only running code would settle a question, say so: give the exact test or command that would settle it, and mark the finding **unverified**. Never infer a library's behavior from its name, types or README.
4. Write each finding as the question a teammate would ask on the PR, followed by the remediation.
5. Give `pass` only when no High or Medium finding remains. In the summary, name the passes that found nothing.

## Passes

Run every pass. Skip one only when the diff can't touch it, and say which ones you skipped.

| # | Pass | Ask | Default severity |
|---|------|-----|------------------|
| 1 | Claims | List every claim in the PR text, docs, API descriptions, code comments and test names. Does the code do exactly that, in every case? Was any note written before a later commit changed the behavior? When the PR says a path doesn't change ("nothing changes with the flag off"), list every changed file that path imports, shared constants and global setup included. | Medium |
| 2 | Library truth | For each library call on a changed path (SDKs, HTTP clients, validators, config loaders, ORMs, queues), open its source. Does it throw or return on failure? What does it do with non-2xx responses, redirects, timeouts and empty bodies? What are its default retries? What does the validator accept? What does it log by itself? | High if data or user actions can be lost; otherwise Medium |
| 3 | Failure classes | For each status or outcome branch, list what can produce it in production: a wrong host, a missing route (the framework's generic 404), a bad credential (401/403), a rate limit (429), a 3xx, a 200 without the expected fields, deploy order, a rollback. Is "final" decided by the domain's code rather than the status class? Is anything acknowledged, skipped or dropped without an alert? | High for silent loss |
| 4 | Rollout | What happens if this ships before its config, secrets, data, flags or migrations exist? With the flag off, partially rolled out, after a rollback? In local dev? Where do environments differ? {{ROLLOUT_NOTES}} | High if production breaks or data is lost |
| 5 | Blast radius | Search every unit in the workspace for other consumers of what changed: routes, error shapes, flags, config keys, credentials, events, cookies, shared types, test kits. Does any of them break or change behavior? | High for an unlisted consumer that breaks |
| 6 | Access | Who can reach this path: which callers, roles or keys? Is input read before it is authenticated? A redirect or return URL taken from input: which layer checks it before a user is sent there? Does that match the acceptance criteria? | High if wider than intended |
| 7 | Numbers | For every constant behind a wait, timeout, retry, limit, batch size, sample split or rounding: is its basis recorded (a measurement, an ADR, an upstream doc)? A spec or comment that only restates the number is not a basis. What does moving it either way cost? | High if users wait on it or money depends on it; otherwise Low |
| 8 | Data validity | For events, metrics and experiments: who is counted, and who is left out without a trace (consent, blockers, regions, timeouts)? What mixes the groups? Can the metric see what it claims to measure? | High if the analysis would be wrong |
| 9 | Personal data | Names, emails, free-text notes, payment or health data in logs, events and errors. That includes what a library logs by itself on failure, and debug logs. | High |
| 10 | Observability | Does the log level match the alerting? Is there one `error` per final failure rather than one per retry? Do the logs carry the IDs on-call needs? | Medium |
| 11 | Input edges | Case normalization, lenient validators, null or zero divisors, negative remainders, rounding, client-side limits against the schema's limits, wrong types before validation, empty collections. | Medium |
| 12 | Test truth | For each test, which line would make it fail if removed or reordered? Flag tests that can't fail, stubs with behavior the real library never has, missing "not called" assertions, environment leaks between tests, test names that contradict the rule, and missing wiring tests at the entry point. | Medium |
| 13 | Acceptance and gates | Is every acceptance criterion met, or moved to a tracked ticket? Flag "someone must switch this later" when no ticket tracks it. Check the repo's own gates too: type-check, lint and config schema declarations. | High for an unmet criterion that no ticket tracks |

## Baseline

Also check the generic items: runtime errors and null handling; performance (N+1 queries, repeated work, unnecessary re-renders); unintended side effects; backwards compatibility of contracts; security (injection, XSS, secrets); and fit with the repo's architecture. Don't block on style.

## Examples

**Anti-pattern:** a coverage row marked ok against a mock.
> Remote config fails → ok (the hook's test mocks the SDK and calls `onError`).

**Corrected:**
> Remote config fails → partial. The test mocks the SDK. In the SDK's client (`lib/client.js`, version from the lockfile), any non-2xx resolves to `{status}` instead of throwing, so `onError` never fires: a 500 waits out the full timeout. Unverified by a run: needs a test with the real SDK and the HTTP layer stubbed to return 500.

**Anti-pattern:** accepting a rule based on the status class.
> 4xx responses are final and 5xx responses are retried. ok.

**Corrected:**
> A missing route or a wrong host makes the framework answer a generic 404 before auth. This code treats that as final, so the event is dropped with a `warn` and no alert fires. Treat only the domain's own "not found" error as final.

**Anti-pattern:** trusting the PR text.
> Description: "if the setting is missing, startup fails". ok.

**Corrected:**
> The config loader merges a default file in every environment, so a missing setting keeps the placeholder and startup succeeds; the first real call fails instead. Either move the placeholder to the test config or correct the description.

## Output

Use the caller's output structure. Without one, give the verdict (`pass`, `pass_with_risks` or `fail`), then the findings by severity (High, Medium, Low, Hardening), each with why, evidence, impact and remediation, and then the passes that found nothing.
