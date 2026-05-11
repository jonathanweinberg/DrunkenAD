# Issue 003: Live Harness Boundary Was Too Specific

Status: Superseded - Corrected in v0.12.1

## Summary

The first `0.12.0` cleanup tried to make the seeded live campaign boundary more
visible, but it made one host implementation too prominent in the public docs.
That was the wrong product direction. The live campaign should be documented as a
generic host-wrapper contract because future labs may use several different
execution, rollback, and workspace-transfer methods.

## Evidence

- The public live-validation guide moved from implicit host assumptions to
  explicit host-method details.
- The README, testing guide, operations runbook, changelog, and issue note also
  repeated those details.
- The release test reinforced that mistake by requiring the public docs to name a
  specific host method instead of requiring host-method neutrality.

## Corrective Outcome

- Supersede the `0.12.0` wording with `0.12.1`.
- Keep public docs generic about live campaign host methods.
- Add a host-method contract page that explains what any implementation must
  provide.
- Keep the checked-in live campaign scripts intact until multiple host methods
  are designed.
- Add regression coverage so public docs do not drift back to one host method.

## Close Criteria

- Public docs and issue notes avoid specific host implementation names.
- `docs/LIVE-CAMPAIGN-HOSTS.md` documents the generic host-wrapper contract.
- Release metadata, changelog, and release-readiness tests agree on `0.12.1`.
- Local parser, docs, unit, and release checks pass.

Closed by the `v0.12.1` corrective documentation release.
