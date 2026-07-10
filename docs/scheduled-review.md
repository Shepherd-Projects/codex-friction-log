# Scheduled reviewer setup

Create this as a Codex desktop automation, not a Windows Task Scheduler job and not a permanently running process.

Recommended configuration:

| Field | Value |
| --- | --- |
| Name | Weekly Codex Friction Review |
| Schedule | Every Monday at 09:00 local time |
| Environment | Local |
| Project | Any stable local Codex project; the log itself is per-user/global |
| Model | `gpt-5.6-sol` |
| Reasoning | `max` |
| Prompt | Exact contents of `docs/reviewer-prompt.md` |

Ask Codex:

```text
Create an active local Codex automation named “Weekly Codex Friction Review”. Run it every Monday at 09:00 local time. Use gpt-5.6-sol with max reasoning. Use the exact prompt in docs/reviewer-prompt.md. Read the automation back after creation and verify its name, schedule, project, local environment, model, reasoning, status, and prompt. Do not create a duplicate if one already exists.
```

## Why the reviewer claims batches

Directly reading and then clearing `friction.jsonl` can delete events appended during the review. `friction-review` instead shares the writer mutex:

1. `friction-review -Claim` moves the current active file to a uniquely named pending batch and immediately creates a fresh active file.
2. `friction-review -List` exposes all recoverable pending batches, including batches left by an earlier failed review.
3. The agent reads every listed batch and writes one durable recommendation report.
4. Only after that report exists does it run `friction-review -Complete -Batch <filename>` for each included batch.

Thus new events survive for next week, reviewed events disappear, and a failed review remains recoverable.

## Expected task output

The scheduled task should return:

- report path;
- number of friction events and projects reviewed;
- prioritized recommended fixes or changes;
- explicit statement that nothing was implemented;
- any unconsumed batch and reason.

The user can then approve, reject, or modify recommendations in that task. The reviewer must not edit projects, global configuration, tools, skills, or instruction files beyond its report and the batch lifecycle.
It must never implement recommendations.

## Changing cadence

Ask Codex to update the existing automation by name. Preserve its prompt, local environment, model, reasoning, and active status unless intentionally changing them.
