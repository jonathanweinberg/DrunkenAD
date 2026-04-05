# Testing DrunkenAD

DrunkenAD now has two test layers:

- Unit tests that mock the Active Directory cmdlets and run locally today.
- Integration tests that are intentionally dormant until a live demo environment is available.

## Unit Tests

The unit suite lives in [tests/DrunkenAD.Unit.Tests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/DrunkenAD.Unit.Tests.ps1).

It focuses on the safety-critical behavior:

- Exact LDAP user resolution
- Literal prefix matching
- Prefix map construction
- No-op detection when nothing changed
- Correct use of `Clear` vs `Replace`
- `-WhatIf` handling

Run it with:

```powershell
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1
```

If you only want the parser gate:

```powershell
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/scripts/Test-DrunkenADSyntax.ps1
```

## Integration Tests

The integration suite lives in [tests/DrunkenAD.Integration.Tests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/DrunkenAD.Integration.Tests.ps1).

It is skipped unless all of the following are present:

- `DRUNKENAD_RUN_INTEGRATION=1`
- `DRUNKENAD_TEST_DC`
- `DRUNKENAD_TEST_DNS_SUFFIX`

Optional:

- `DRUNKENAD_TEST_USER_OU`

Example:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
$env:DRUNKENAD_TEST_USER_OU = 'OU=Demo Users,DC=contoso,DC=com'
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1 -IncludeIntegration
```

## What The Integration Tests Will Validate

When the demo AD environment is ready, the suite will validate:

- the `drink` schema attribute is enabled
- prefixed writes work end-to-end
- literal prefixes with regex metacharacters still behave correctly
- replacing one prefix does not disturb other prefixes
- temporary test users are cleaned up afterward

## Recommended Workflow

For future changes, the clean loop is:

1. Add or update unit tests first.
2. Run the local mocked suite.
3. Use `-WhatIf` against the live environment before any write.
4. Run the integration suite in the demo AD environment.
5. Keep the integration suite green before merging risky attribute-manipulation changes.

## CI Notes

The repository includes a starter GitHub Actions workflow at [.github/workflows/powershell-ci.yml](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/.github/workflows/powershell-ci.yml).

Today it runs:

- syntax parsing through [scripts/Test-DrunkenADSyntax.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/scripts/Test-DrunkenADSyntax.ps1)
- the unit test suite through [tests/Invoke-DrunkenADTests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1)

That split is deliberate: unit coverage stays always-on, while integration coverage stays environment-driven.
