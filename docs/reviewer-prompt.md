# Weekly reviewer prompt

```text
Review this Windows user's global Codex friction log. Advisory mode only: recommend fixes or changes; never implement them, edit projects, install tools, alter configuration, or modify instruction files.

Use the installed `friction-review` command. First run `friction-review -Claim` and parse its JSON. If `busy` is true, report that another review owns the batch, perform no other review command or write, and return the exact final statement below. Otherwise retain the returned `lease`, then run `friction-review -List -Lease <lease>`. Read every listed pending JSONL batch, including batches retained from an earlier failed run. Validate each nonblank line as one object with `ts`, `cwd`, `blocked`, and `friction`.

If there are no pending events, run `friction-review -Release -Lease <lease>`, report "No friction recorded this period.", and do not create an empty recommendations report.

Otherwise group repeated or related events without hiding one-off high-impact blockers. Produce a concise prioritized list. For each recommendation include: affected project(s), event count, observed friction pattern, recommended fix/change, expected benefit, and meaningful risk or tradeoff. Evidence must come from the log; label inference as inference. Do not diagnose inside or rewrite the source log.

Write the complete recommendations first to a durable Markdown file under `%USERPROFILE%\.codex\friction-reports\`, using a UTC timestamp in the filename. Include batch filenames and event counts so consumption is auditable. Do not include secrets or unnecessary raw payloads.

Only after the report file is successfully written and re-read, run `friction-review -Complete -Lease <lease> -Batch <filename>` once for each batch included in that report, then run `friction-review -Release -Lease <lease>`. Never complete an unread, invalid, omitted, or unreported batch. If any error prevents a durable complete report, leave the lease and batches in place; a later run can reclaim a lease older than 24 hours. New events in `%USERPROFILE%\.codex\friction.jsonl` belong to the next run and must remain untouched.

Return the report path, reviewed event/project counts, prioritized recommendations, completed batch names, any retained batch with reason, and the exact statement: "No fixes were implemented."
```
