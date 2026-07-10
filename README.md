# Codex Friction Log

Codex can hit unexpected tooling or environment friction, silently work around it, and finish the task without leaving evidence. This installs one global instruction and one tiny command so those moments become a reviewable per-user log.

```json
{"ts":"2026-07-10T09:15:00.0000000+00:00","cwd":"C:\\work\\project-a","blocked":"run formatter","friction":"formatter executable was missing"}
```

The logger records the blocked intent and observed obstacle only. Diagnosis and fix ideas belong in the later review.

## Properties

- One log for every Codex project and session owned by the same Windows user.
- Immediate capture: first recognition, before retry or workaround; never retrospective.
- Silent, fail-open append. Logger failure never interrupts the primary task.
- No daemon, service, watcher, background PowerShell process, or MCP server.
- Compact newline-delimited JSON: `ts`, `cwd`, `blocked`, `friction`.
- Concurrency-safe writer, single-owner review lease, and lossless weekly batch consumption.
- Idempotent install; reversible uninstall; log retained by default.

## Requirements

- Windows.
- Windows PowerShell 5.1 or newer.
- Codex loading `%USERPROFILE%\.codex\AGENTS.md`.
- Codex desktop automation support for the optional scheduled reviewer.

## Let Codex set it up

Give Codex this repository URL and say:

```text
Set up Codex Friction Log from https://github.com/Shepherd-Projects/codex-friction-log on this Windows user. Run setup.ps1, run tests/verify.ps1, then follow docs/scheduled-review.md to create the weekly recommendation-only reviewer. Do not delete or overwrite unrelated AGENTS.md content.
```

Restart already-open Codex tasks after setup so they reload the global instruction.

## Manual setup

```powershell
git clone https://github.com/Shepherd-Projects/codex-friction-log.git
cd codex-friction-log
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

`setup.ps1` calls the idempotent `install.ps1`, then proves both installed commands resolve in a fresh PowerShell process.

Installed paths:

| Purpose | Path |
| --- | --- |
| Global instruction | `%USERPROFILE%\.codex\AGENTS.md` |
| Logger command | `%USERPROFILE%\.codex\bin\friction.ps1` |
| Review batch command | `%USERPROFILE%\.codex\bin\friction-review.ps1` |
| Active log | `%USERPROFILE%\.codex\friction.jsonl` |
| Recoverable pending batches | `%USERPROFILE%\.codex\friction-pending\` |
| Current review lease | `%USERPROFILE%\.codex\friction-review.lock` |

The installer adds `%USERPROFILE%\.codex\bin` to the user `PATH`. New PowerShell and Codex processes inherit it. Nothing remains running after setup.

## Runtime behavior

At a qualifying friction point, Codex runs:

```powershell
friction '<blocked intent>' '<observed obstacle>'
```

The command appends one UTF-8 JSON line and exits without output. The working directory identifies the affected project. A named mutex prevents concurrent writers from interleaving lines.

Invalid arguments, serialization errors, an unavailable path, or a one-second mutex timeout produce a silent no-op. Losing an event is preferable to distracting or blocking the task being performed.

This is instruction-driven, not a native Codex event hook. A model can still fail to recognize or follow the instruction. Project-level `AGENTS.md` rules can also conflict with the global rule.

## Weekly reviewer

The recommended automation runs weekly, uses a strong model, creates recommendations only, and then consumes exactly the rows included in its durable report. New rows arriving during review stay in the active log for the next run.

See [scheduled reviewer setup](docs/scheduled-review.md) and the [exact reviewer prompt](docs/reviewer-prompt.md).

Recommended configuration:

- Cadence: Monday, 09:00 local time.
- Model: `gpt-5.6-sol` when available.
- Reasoning: `max`.
- Environment: local.
- Action boundary: recommend changes; never implement them.

## Privacy and retention

The log is plaintext on the local machine. It contains timestamps, project working directories, blocked intents, and observed obstacles. It is never sent anywhere by these scripts.

Do not put secrets, tokens, credentials, customer data, or sensitive file contents in logger arguments. The global instruction intentionally asks for compact obstacle descriptions.

Weekly review uses a claim/complete lifecycle:

1. One reviewer acquires a 24-hour lease; overlapping runs exit without touching batches.
2. Active rows move under the same writer mutex into a recoverable pending batch.
3. New events continue in a fresh active log.
4. The reviewer writes a durable recommendation report.
5. Only batches represented in that report are deleted; the owner then releases its lease.

If review fails before completion, the pending batch and lease remain. A later run can reclaim a lease older than 24 hours. This prevents silent data loss and duplicate review.

## Uninstall

Remove installed commands, the managed instruction block, and the exact user `PATH` entry while preserving logs:

```powershell
.\uninstall.ps1
```

Also delete active and pending friction data:

```powershell
.\uninstall.ps1 -RemoveData
```

Uninstall does not delete unrelated `%USERPROFILE%\.codex\AGENTS.md` content or other files in `%USERPROFILE%\.codex\bin`.

## Test

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

The isolated suite covers syntax, clean setup, repeated install, malformed managed markers, silent/invalid calls, multiple project directories, 32 concurrent writers, overlapping reviewer rejection, stale-lease recovery, lossless batch consumption, safe uninstall, and proof that production files and user `PATH` were untouched.

## License

[MIT](LICENSE)
