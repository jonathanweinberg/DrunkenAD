# Windows Server Live Validation - 2026-05-07

This sanitized historical record summarizes the May 7, 2026 validation pass
against an authorized Windows Server 2025 AD lab. It is not current release
signoff. Exact endpoints, domain/account identifiers, connection details,
rollback identifiers, credential-handling instructions, and raw directory
screenshots have been removed from the current documentation.

## Historical Results

The recorded run used Windows PowerShell 5.1 and Pester 5.7.1. Source staging
excluded ignored credentials and live-result files.

- Parser/import gate: passed.
- Exported module commands at that revision: 11.
- Non-integration suite: 43 passed, 0 failed, 0 skipped, 4 not run.
- Combined suite with live integration: 47 passed, 0 failed, 0 skipped.
- Campaign smoke suite: 4 passed, 0 failed.

| Campaign Phase | Recorded Result | Duration Seconds |
| --- | --- | ---: |
| Preflight | Ready for user writes | 0.144 |
| Smoke | 4 passed, 0 failed | 5.451 |
| Seed reconcile | 3,000 total, 0 failures | 96.174 |
| CSV ingestion | 3,000 processed, 0 failures | 610.424 |
| Projection | 3,000 processed, 0 failures | 877.803 |
| CRUD | 300 processed, 0 failures | 270.731 |

Three regional seed groups each contained 1,000 synthetic users. A sampled
account from each group had 12 final drink values and retained its unrelated
stability marker. Raw account-level examples are intentionally not published.

## Schema Lesson

The historical target initially had the drink attribute but did not permit it
on user objects. After an authorized schema modification, explicit schema-cache
refresh was needed before real writes succeeded. Schema presence alone was
therefore insufficient evidence of write readiness.

This is historical evidence, not authorization to modify another forest. Use
[SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md) for the current guarded workflow.

## Reproduction Boundary

Use [TESTING.md](TESTING.md), [LIVE-VALIDATION.md](LIVE-VALIDATION.md), and
[LIVE-CAMPAIGN-HOSTS.md](LIVE-CAMPAIGN-HOSTS.md) for current procedures. Supply
targets and credentials privately, establish rollback readiness, run bounded
tests, and verify cleanup. Never copy live configuration or raw directory
artifacts into public docs, issues, pull requests, or commits.

Historical screenshots and their HTML sources are no longer included in the
current tree. This removal does not erase copies in older Git commits or
previously published artifacts; history remediation is a separate coordinated
operation.
