# DrunkenAD Diagrams

This page keeps the Mermaid diagrams and their generated infographic plates
together. The Mermaid files under `docs/diagrams/` are the editable source of
truth. The PNG images under `docs/images/documentation-suite-2026-05-07/` and
`docs/images/documentation-suite-2026-05-11/` are page-facing explanations with
labels, examples, and workflow context.

## Product Overview

![DrunkenAD overview image](images/documentation-suite-2026-05-07/drunkenad-overview.png)

Use this image when introducing the whole project: schema readiness, CSV
ingestion, projection, namespace updates, live validation, and reporting all
around the same `drink` attribute model.

## Module Layout

![Module layout image](images/documentation-suite-2026-05-11/module-layout.png)

```mermaid
flowchart LR
    PRIVATE["Private helpers<br/>Core.ps1<br/>PrefixMap.ps1<br/>ProjectionMap.ps1<br/>CsvMapping.ps1<br/>SchemaStatus.ps1"]
    ROOT["DrunkenAD.psm1<br/>deterministic dot-source loader"]
    PUBLIC["12 exported commands<br/>Get / Set / Remove<br/>CSV + projection<br/>schema readiness<br/>compatibility wrappers"]
    MANIFEST["DrunkenAD.psd1<br/>FunctionsToExport parity<br/>ModuleVersion 0.13.2<br/>PowerShell 5.1"]
    RELEASE["Source readiness<br/>syntax + docs<br/>trusted Pester 5.7.1<br/>export parity<br/>architecture atlas"]

    PRIVATE --> ROOT
    ROOT --> PUBLIC
    ROOT --> MANIFEST
    MANIFEST --> RELEASE
```

Source file: [diagrams/module-layout.mmd](diagrams/module-layout.mmd)

## Use-Case Map

![Use-case map image](images/documentation-suite-2026-05-07/use-case-map.png)

```mermaid
flowchart LR
    subgraph Sources["Operational sources"]
        HR["HR export"]
        IAM["IAM workflow"]
        APP["Application config"]
        SYNC["Sync engine"]
    end

    subgraph Drink["User drink namespace store"]
        FLAGS["Flags-"]
        PROFILE["Profile-"]
        ROUTING["Routing-"]
        TENANT["Tenant-"]
        SYNCNS["Sync-"]
    end

    subgraph Consumers["Directory-aware consumers"]
        PROV["Provisioning"]
        MAIL["Mail routing"]
        AUDIT["Audit review"]
        APPS["Internal apps"]
    end

    HR --> PROFILE
    IAM --> FLAGS
    APP --> ROUTING
    APP --> TENANT
    SYNC --> SYNCNS
    FLAGS --> AUDIT
    PROFILE --> APPS
    ROUTING --> MAIL
    TENANT --> PROV
    SYNCNS --> SYNC
```

Source file: [diagrams/use-case-map.mmd](diagrams/use-case-map.mmd)

## Namespace Write Model

![Namespace write model image](images/documentation-suite-2026-05-07/namespace-write-model.png)

```mermaid
flowchart TD
    START["Caller provides DataMap and identity"] --> VALIDATE["Validate nonblank, non-overlapping literal prefixes"]
    VALIDATE --> READY["Check drink is writable on user"]
    READY --> RESOLVE["Resolve exactly one AD user"]
    RESOLVE --> READ["Read current drink values"]
    READ --> FILTER["Remove OrdinalIgnoreCase prefix matches"]
    FILTER --> MERGE["Add replacement values for owned prefixes"]
    MERGE --> COMPARE["Compare multivalue elements without delimiter flattening"]
    COMPARE --> DECIDE{"Any final drink values?"}
    DECIDE -->|Yes| REPLACE["Set-ADUser -Replace drink"]
    DECIDE -->|No| CLEAR["Set-ADUser -Clear drink"]
    REPLACE --> RETURN["Return final values when PassThru is used"]
    CLEAR --> RETURN
```

Source file: [diagrams/namespace-write-model.mmd](diagrams/namespace-write-model.mmd)

## CSV Ingestion Flow

![CSV ingestion flow image](images/documentation-suite-2026-05-07/csv-ingestion-flow.png)

```mermaid
flowchart LR
    CSV["CSV rows"] --> LOCAL["Local preflight<br/>paths + required columns"]
    MAP["JSON or hashtable namespace map"] --> LOCAL
    LOCAL --> OWNERSHIP["Validate map shape<br/>nonblank, non-overlapping prefixes"]
    OWNERSHIP --> IDENTITIES["Normalize SamAccountName<br/>trim + case-insensitive uniqueness"]
    IDENTITIES --> ROW["Build per-row DataMap<br/>skip blank mapped values"]
    ROW --> READY["Verify drink write readiness"]
    READY --> WRITE["Set-ADUserDrinkData"]
    WRITE --> AD["Active Directory user drink"]
    AD --> READBACK["Sample read-back validation"]
    READBACK --> REPORT["Processed, failures, samples"]
```

Source file: [diagrams/csv-ingestion-flow.mmd](diagrams/csv-ingestion-flow.mmd)

## Schema Readiness Flow

![Schema readiness flow image](images/documentation-suite-2026-05-07/schema-readiness-flow.png)

```mermaid
flowchart TD
    CHECK["Test-ADDrinkAttributeReadyForUserWrite"] --> EXISTS{"drink exists?"}
    EXISTS -->|No| MISSING["Stop: AttributeMissing"]
    EXISTS -->|Yes| DEFUNCT{"drink defunct?"}
    DEFUNCT -->|Yes| BLOCKDEF["Stop: AttributeDefunct"]
    DEFUNCT -->|No| USERCLASS{"Allowed on user class?"}
    USERCLASS -->|No| ENABLE["Enable mayContain on schema master"]
    ENABLE --> REFRESH["Refresh schema cache and verify"]
    USERCLASS -->|Yes| READY["Ready for user writes"]
    REFRESH --> READY
```

Source file: [diagrams/schema-readiness-flow.mmd](diagrams/schema-readiness-flow.mmd)

## Live Validation Ladder

![Live validation ladder image](images/documentation-suite-2026-05-07/live-validation-ladder.png)

```mermaid
flowchart TD
    ROLLBACK["1. Rollback evidence + operator confirmation"] --> TRUST["2. Syntax + trusted Pester 5.7.1"]
    TRUST --> INTEGRATION["3. Opt-in live integration tests"]
    INTEGRATION --> READINESS["4. Domain, services + schema readiness"]
    READINESS --> INPUTS["5. Per-run manifest, CSV + config with SHA-256"]
    INPUTS --> IDENTITIES["6. Exact unique manifest/CSV identity set"]
    IDENTITIES --> SEED["7. Bounded seed reconcile; fail closed on unexpected users"]
    SEED --> DATA["8. CSV ingestion + attribute projection"]
    DATA --> CRUD["9. CRUD sample + read-back validation"]
    CRUD --> SUMMARY["10. campaign-summary.json + operator notes"]
```

Source file: [diagrams/live-validation-ladder.mmd](diagrams/live-validation-ladder.mmd)

## Live Campaign Profiles

![Live campaign profiles image](images/documentation-suite-2026-05-11/live-campaign-profiles.png)

```mermaid
flowchart LR
    QUICK["Quick<br/>30 seed users<br/>3 CRUD samples per region"]
    STANDARD["Standard<br/>300 seed users<br/>10 CRUD samples per region"]
    FULL["Full<br/>3,000 seed users<br/>100 CRUD samples per region<br/>default"]
    PREFLIGHT["Campaign preflight<br/>rollback evidence + confirmation<br/>run-specific inputs + SHA-256<br/>exact manifest/CSV identity set"]
    HARNESS["Bounded live execution<br/>campaign root only<br/>no implicit prune or account adoption<br/>CSV + projection + CRUD"]
    SUMMARY["campaign-summary.json<br/>operator notes<br/>profile-derived totals"]

    QUICK --> PREFLIGHT
    STANDARD --> PREFLIGHT
    FULL --> PREFLIGHT
    PREFLIGHT --> HARNESS
    HARNESS --> SUMMARY
```

Source file: [diagrams/live-campaign-profiles.mmd](diagrams/live-campaign-profiles.mmd)

## Release Readiness

![Release readiness image](images/documentation-suite-2026-05-11/release-readiness.png)

```mermaid
flowchart LR
    INPUTS["Inputs<br/>DrunkenAD.psd1<br/>DrunkenAD.psm1<br/>Public commands<br/>Private helpers<br/>docs<br/>tests"]
    TRUST["Trusted test boundary<br/>exact Pester 5.7.1 manifest<br/>six tracked top-level test files<br/>never tests/Live/results"]
    SCRIPT["scripts/Test-DrunkenADRelease.ps1"]
    CHECKS["Local source gate<br/>manifest metadata<br/>clean import + export parity<br/>syntax + docs + architecture<br/>94 passed; 6 integration not run"]
    CI["Remote CI matrix<br/>Ubuntu pwsh<br/>macOS pwsh<br/>Windows pwsh<br/>Windows PowerShell 5.1<br/>no PSGallery publish"]

    INPUTS --> SCRIPT
    TRUST --> SCRIPT
    SCRIPT --> CHECKS
    CHECKS --> CI
```

Source file: [diagrams/release-readiness-flow.mmd](diagrams/release-readiness-flow.mmd)
