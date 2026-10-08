# DrunkenAD Operations Runbook

This runbook is for operators who need to validate, write, ingest, project, or
remove DrunkenAD values in a live Active Directory environment.

See the current [schema readiness flow](DIAGRAMS.md#schema-readiness-flow).

The source diagram for this page lives at
[diagrams/schema-readiness-flow.mmd](diagrams/schema-readiness-flow.mmd).

## Before Any Live Write

1. Confirm you are targeting the intended domain controller.
2. Import the module.
3. Check schema readiness.
4. Confirm the workflow's owned prefixes.
5. Use `-WhatIf` where the command supports it.

```powershell
Import-Module .\DrunkenAD\DrunkenAD.psd1 -Force

Test-ADDrinkAttributeReadyForUserWrite `
    -Server 'dc01.contoso.com' `
    -PassThru | Format-List
```

If `ReadyForUserWrite` is not `True`, stop and follow
[SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md).

## Generic Namespace Write

Use `Set-ADUserDrinkData` for direct namespace writes:

```powershell
Set-ADUserDrinkData `
    -SamAccountName 'alice.bennett' `
    -DataMap @{
        'AppProfile-' = @('Tier=Gold', 'Region=NA')
        'Flags-'   = @('Enabled', 'Audited')
    } `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

Remove `-WhatIf` only after the preview matches the intended prefix ownership.

## CSV Ingestion

Use the sample mapping as a starting point:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath .\examples\data\drink-ingestion-sample.csv `
    -ConfigPath .\examples\data\drink-ingestion-config.json `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

The sample CSV map owns `CsvProfile-`, `Flags-`, `CsvRouting-`, `Tenant-`, and
`Sync-`, separate from the default projection. Custom maps must also avoid
unintended overlap. Entirely blank mapped namespaces remain unchanged unless
`-ClearBlankNamespaces` is supplied. Incomplete CSV records fail before AD
access. Confirmation uses refreshed counts and stops if the approved delta
changes before writing. See [CSV guidance](HOW-TO-INGEST-CSV.md#blank-cells-and-existing-imports).

## Attribute Projection

Use projection when AD attributes should be copied into namespaced records:

```powershell
Set-ADUserDrinkProjection `
    -SamAccountName 'alice.bennett' `
    -IncludeDefaultAttributeMap `
    -AttributeMap @{ 'Org-' = @('department', 'title') } `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Projection replaces the prefixes in its effective attribute map. Review the map
before using it in the same prefix space as CSV ingestion.

## Removal

Remove only the prefixes you intend to own:

```powershell
Remove-ADUserDrinkData `
    -SamAccountName 'alice.bennett' `
    -Prefixes @('Scenario-', 'Literal[01]-') `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

## Activity Logs

The compatibility writer's `-EnableLogging` uses the current user's local
application-data directory, under `DrunkenAD/logs-v1`. If that private root is
unavailable, logging warns and requires an explicit path instead of falling
back to shared temporary storage. It reuses `activity.log`, rotating to
`activity.previous.log`, with at most 1 MiB per file. Entries carry a module
session identifier, ObjectGUID, and counts, not account names or attribute
values. Treat GUIDs as persistent identifiers and protect logs accordingly.
Rotation is restricted to recognized module-owned files and rejects links.
Older GUID-named logs are not automatically deleted.
Preview mode does not append or rotate activity logs.

Supply one `-LogPath` across commands for a caller-managed batch log. Explicit
paths are append-only and are not automatically rotated; manage their access
and retention. Logging is best effort: a failure emits a warning, not a false
directory-write failure. A `Written` status is evidence that the directory call
succeeded, not a guarantee that a log record was stored.
Logging warnings honor `-WarningAction SilentlyContinue` and `Ignore`.
Other warning preferences, including `Stop` and `Inquire`, remain nonterminating
for logging only, so a failed log cannot invalidate a completed directory write.

## Live Validation

Use the live campaign when you need end-to-end evidence across schema readiness,
temporary smoke writes, seeded users, CSV ingestion, projection, and CRUD.

![Live validation ladder](images/documentation-suite-2026-05-07/live-validation-ladder.png)

![Live campaign profiles](images/documentation-suite-2026-05-11/live-campaign-profiles.png)

The source diagram for this validation path lives at
[diagrams/live-validation-ladder.mmd](diagrams/live-validation-ladder.mmd).
The profile source diagram lives at
[diagrams/live-campaign-profiles.mmd](diagrams/live-campaign-profiles.mmd).

Before running a live campaign:

- confirm a VM snapshot or equivalent rollback point
- preview the host campaign with `-WhatIf` before approving mutation
- provide `DRUNKENAD_SEED_PASSWORD` through the guest process environment only
- never write the seed password to a tracked file or run artifact
- confirm that `tests/Live/results/` is ignored by Git
- confirm the selected host wrapper can create or verify the rollback point,
  expose the repository workspace, run the guest-side script, and collect reports
- verify the operator notes contain the run-specific input paths and SHA-256 hashes
- stop if an unexpected user exists under the bounded campaign root; the harness will not prune it
- use a timeout long enough for thousands of AD reads and writes

Start with the quick profile when you only need a live sanity pass:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1 `
    -CampaignProfile Quick
```

Use `Standard` for 300 seeded users and `Full` for the full 3,000-user
campaign. `Full` is the default profile for compatibility with earlier runs.

The May 7, 2026 WinServer campaign took about 31 minutes for 3,000 seed users,
3,000 CSV writes, 3,000 projection writes, and 300 CRUD samples.

## Rollback

For the lab VM, restore the pre-mutation snapshot. For a broader AD forest,
follow the organization's schema-change recovery process. This repo documents
the checks and guardrails, but it does not automate rollback from schema changes.
