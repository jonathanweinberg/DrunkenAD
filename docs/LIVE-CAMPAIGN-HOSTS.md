# Live Campaign Host Methods

The seeded live campaign is the high-fidelity validation path for DrunkenAD. It
proves schema readiness, seeded users, CSV ingestion, projection, CRUD samples,
and report generation against a live Active Directory lab.

The campaign is intentionally split into two responsibilities:

- the DrunkenAD guest-side campaign script, which performs the AD work
- a host wrapper, which prepares the lab, launches the guest-side script, and
  collects evidence

This page defines the host-method contract without naming a specific
virtualization, remoting, file-share, or lab-control implementation. Method
specifics belong in wrapper scripts or in future method-specific runbooks.

## Host Wrapper Responsibilities

A host wrapper must make a live campaign repeatable enough that another operator
can understand what happened after the run. At minimum, it should:

- choose the `Quick`, `Standard`, or `Full` campaign profile
- use the profile's fixed seed count without an independent override
- create or verify a rollback point before mutation
- make the repository workspace available where the guest-side script runs
- create a unique per-run manifest, CSV, and config bundle
- record the SHA-256 hash of each run input in operator notes
- run the guest-side campaign with literal-safe paths and profile settings
- capture standard output, errors, summary JSON, and operator notes
- return a nonzero exit code when the guest-side campaign fails
- avoid writing secrets or durable credentials into tracked files

The wrapper may use any host method that satisfies those responsibilities. The
public docs should describe the contract, not the method.

## Snapshot Or Rollback Point

The campaign changes live directory objects, so a rollback point is mandatory
for seeded runs. A host method can satisfy this by creating a VM snapshot,
confirming a disposable lab restore point, or documenting another equivalent
rollback path.

Operator notes should capture:

- rollback point name or identifier
- timestamp
- target lab identity
- campaign profile
- seed count
- run-input paths and SHA-256 hashes
- any manual preflight checks

If the host method cannot create the rollback point itself, it should fail unless
the operator provides proof that an acceptable rollback point already exists.

## Guest Or Remote Workspace

The guest-side campaign needs access to the repository, its run-specific seed
data and CSV ingestion config, and a writable results directory. A host method can provide
that workspace through a shared folder, staged archive, remote copy, mounted
volume, or another transport.

The workspace contract is:

- module source is importable from the guest-side PowerShell session
- `tests/Live/results/<run-id>/inputs/` contains the exact manifest, CSV, and config used by the run
- manifest and CSV identities are nonblank, unique, and equal as sets
- `tests/Live/results/<run-id>/` is writable
- generated outputs remain ignored by Git

The guest campaign owns only its bounded root OU. An unexpected account under
that root is a blocking condition, not a prune candidate. A same-named account
outside the root is never moved into campaign ownership.

The generic docs should avoid hard-coded transport paths. Put those details in
the wrapper or a method-specific runbook.

## Result Collection

Every host method should collect the same evidence shape so release reviewers do
not need to understand the transport mechanism first.

Required outputs:

- `operator-notes.md`
- `guest-output.txt`
- `campaign-summary.json`
- any smoke-test output produced by the guest-side script

Recommended outputs:

- a short cross-project excerpt for handoffs
- copied console transcript when available
- wrapper diagnostics when launch or workspace setup fails

Use `campaign-summary.json` as the canonical machine-readable result. The
summary should include status, phase counts, durations, seed totals, CRUD sample
counts, and failure context when the campaign does not pass.

## Credential Handling

Credentials are operator-owned inputs. A host method must not require secrets in
tracked files and should prefer an environment variable, local password file,
platform credential store, or interactive prompt.

Credential handling rules:

- never commit secrets or live passwords
- provide `DRUNKENAD_SEED_PASSWORD` only through the guest process environment for approved mutation
- permit `-WhatIf` preview without requiring the seed password
- keep credential-adjacent receipts under `tests/Live/results/`
- restrict local credential files to the operator account when possible
- redact credentials from operator notes and console output
- treat failed authentication as a host-method failure, not a module failure

## Documentation Expectations

When adding a new host method, document only the method-specific setup in its own
runbook. Keep the main README, testing guide, live-validation guide, and
operations runbook focused on:

- when to choose integration tests versus the seeded campaign
- which campaign profile to run first
- what rollback and workspace guarantees must exist
- where ignored outputs are written
- which release gates prove the branch

That keeps the project ready for several live-campaign methods without making
one method look like the product boundary.
