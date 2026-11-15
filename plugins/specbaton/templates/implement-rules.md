<!-- specbaton:implement-rules -->
## Implementing a change (specbaton)

- A change's tasks are implemented by a subagent on the model in `implement.model` of `.claude/specbaton.json`, so this session's model is kept for exploring, proposing, checking each unit and fixing the reviewer's findings.
- When a change's `tasks.md` is ready, offer `/specbaton:implement <change>` in one line and wait. Name the mode and the model from the settings, and how many pending groups or tasks it holds. The tasks are ready after `/specbaton-reviewer:plan` when the reviewer is set up, and right after `/opsx:propose` otherwise.
- When I ask to implement in my own words, use `/specbaton:implement`. When I type `/opsx:apply`, run it as it is.
- The reviewer's findings, of the plan or the code, are fixed in this session, not by the implementer.
