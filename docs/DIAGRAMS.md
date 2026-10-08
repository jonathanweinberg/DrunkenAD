# DrunkenAD Diagrams

This page keeps the Mermaid diagrams and their generated infographic plates
together. The Mermaid files under `docs/diagrams/` are the editable source of
truth. The PNG images under `docs/images/documentation-suite-2026-05-07/` and
`docs/images/documentation-suite-2026-05-11/` are dated historical illustrations, not current write or release contracts.
The Mermaid diagrams below and the interactive atlas describe current behavior.

## Product Overview

![DrunkenAD overview image](images/documentation-suite-2026-05-07/drunkenad-overview.png)

Use this image when introducing the whole project: schema readiness, CSV
ingestion, projection, namespace updates, live validation, and reporting all
around the same `drink` attribute model.

## Module Layout

Historical plate: [Module layout image](images/documentation-suite-2026-05-11/module-layout.png). The Mermaid diagram below is current.

```mermaid
flowchart LR
    PRIVATE["Private helpers<br/>Core.ps1 + WriteOperation.ps1<br/>PrefixMap.ps1<br/>ProjectionMap.ps1<br/>CsvMapping.ps1<br/>SchemaStatus.ps1"]
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

Historical plate: [Namespace write model image](images/documentation-suite-2026-05-07/namespace-write-model.png). The Mermaid diagram below is current.

```mermaid
flowchart TD
    START["Caller provides DataMap and identity"] --> VALIDATE["Validate nonblank, non-overlapping literal prefixes"]
    VALIDATE --> READY["One readiness context<br/>effective DC + schema length bound"]
    READY --> RESOLVE["Resolve exactly one AD user on that DC"]
    RESOLVE --> PLAN["Partition owned values<br/>validate desired value lengths"]
    PLAN --> DELTA["Case-sensitive Remove/Add delta<br/>only for owned prefixes"]
    DELTA --> DECIDE{"Changes and ShouldProcess approval?"}
    DECIDE -->|Yes| WRITE["One Set-ADUser on the same DC<br/>Remove then Add; never Clear or Replace"]
    DECIDE -->|No| RETURN["PassThru returns computed snapshot preview"]
    WRITE --> RETURN
```

Source file: [diagrams/namespace-write-model.mmd](diagrams/namespace-write-model.mmd)

## CSV Ingestion Flow

Historical plate: [CSV ingestion flow image](images/documentation-suite-2026-05-07/csv-ingestion-flow.png). The Mermaid diagram below is current.

```mermaid
flowchart LR
    CSV["CSV rows"] --> LOCAL["Local preflight<br/>paths + required columns"]
    MAP["JSON or hashtable namespace map"] --> LOCAL
    LOCAL --> OWNERSHIP["Validate map shape<br/>nonblank, non-overlapping prefixes"]
    OWNERSHIP --> IDENTITIES["Normalize SamAccountName<br/>trim + case-insensitive uniqueness"]
    IDENTITIES --> READY["One readiness context<br/>pin effective DC"]
    READY --> ROW["Preflight every usable row<br/>resolve identity + validate value lengths"]
    ROW --> WRITE["Shared private writer<br/>prefix-scoped Remove/Add"]
    WRITE --> AD["Active Directory user drink"]
    AD --> REPORT["Stream per-row computed previews"]
    WRITE -->|Runtime failure| FAILURE["Stop with completed / failed / pending counts<br/>earlier rows are not rolled back"]
```

Source file: [diagrams/csv-ingestion-flow.mmd](diagrams/csv-ingestion-flow.mmd)

## Schema Readiness Flow

Historical plate: [Schema readiness flow image](images/documentation-suite-2026-05-07/schema-readiness-flow.png). The Mermaid diagram below is current.

```mermaid
flowchart TD
    CHECK["Test-ADDrinkAttributeReadyForUserWrite"] --> EXISTS{"drink exists?"}
    EXISTS -->|No| MISSING["Stop: AttributeMissing"]
    EXISTS -->|Yes| DEFUNCT{"drink defunct?"}
    DEFUNCT -->|Yes| BLOCKDEF["Stop: AttributeDefunct"]
    DEFUNCT -->|No| GRAPH["Traverse user inheritance and auxiliary classes<br/>may / systemMay / must / systemMustContain"]
    GRAPH --> VALID{"Complete valid graph?"}
    VALID -->|No| BLOCKGRAPH["Fail closed: schema lookup or cycle error"]
    VALID -->|Yes| USERCLASS{"drink allowed?"}
    USERCLASS -->|No| BLOCKUSER["Stop: NotAllowedOnUserClass<br/>no automatic schema mutation"]
    USERCLASS -->|Yes| READY["Ready for user writes on selected DC"]
    ADMIN["Separately authorized schema administrator"] --> ENABLE["Guarded mayContain change on schema master"]
    ENABLE --> REFRESH["RootDSE schemaUpdateNow<br/>refresh and verify; report failure honestly"]
    REFRESH --> CHECK
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

Historical plate: [Release readiness image](images/documentation-suite-2026-05-11/release-readiness.png). The Mermaid diagram below is current.

```mermaid
flowchart LR
    INPUTS["Inputs<br/>DrunkenAD.psd1<br/>DrunkenAD.psm1<br/>Public commands<br/>Private helpers<br/>docs<br/>tests"]
    TRUST["Trusted test boundary<br/>exact Pester 5.7.1 manifest<br/>eight allowlisted test files<br/>never tests/Live/results"]
    SCRIPT["scripts/Test-DrunkenADRelease.ps1"]
    CHECKS["Local source gate<br/>manifest + complete FileList<br/>clean import + export parity<br/>syntax + docs + architecture<br/>fail on discovery or container errors"]
    CI["Remote CI matrix<br/>Ubuntu pwsh + macOS pwsh<br/>Windows pwsh + PowerShell 5.1<br/>integration remains opt-in<br/>no PSGallery publish"]

    INPUTS --> SCRIPT
    TRUST --> SCRIPT
    SCRIPT --> CHECKS
    CHECKS --> CI
```

Source file: [diagrams/release-readiness-flow.mmd](diagrams/release-readiness-flow.mmd)
