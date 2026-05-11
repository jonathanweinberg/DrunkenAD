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
    PUBLIC["Public commands<br/>Get / Set / Remove<br/>Import CSV<br/>Projection<br/>Schema readiness"]
    MANIFEST["DrunkenAD.psd1<br/>FunctionsToExport parity<br/>ModuleVersion 0.11.0"]
    RELEASE["Release readiness<br/>syntax<br/>docs<br/>unit tests<br/>exported commands<br/>manifest metadata"]

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
    START["Caller provides DataMap and identity"] --> READY["Check drink is writable on user"]
    READY --> RESOLVE["Resolve exactly one AD user"]
    RESOLVE --> READ["Read current drink values"]
    READ --> FILTER["Remove values matching owned prefixes"]
    FILTER --> MERGE["Add replacement values for owned prefixes"]
    MERGE --> DECIDE{"Any final drink values?"}
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
    CSV["CSV rows"] --> VALIDATE["Validate required columns"]
    MAP["JSON or hashtable namespace map"] --> VALIDATE
    VALIDATE --> ROW["Build per-row DataMap"]
    ROW --> WRITE["Set-ADUserDrinkData"]
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
    SNAP["Snapshot or rollback point"] --> PARSE["Parser gate"]
    PARSE --> UNIT["Unit tests"]
    UNIT --> INTEGRATION["Live integration tests"]
    INTEGRATION --> SMOKE["Campaign smoke validation"]
    SMOKE --> SEED["Seed reconcile"]
    SEED --> CSV["CSV ingestion"]
    CSV --> PROJECTION["Attribute projection"]
    PROJECTION --> CRUD["CRUD sample validation"]
    CRUD --> SUMMARY["campaign-summary.json"]
```

Source file: [diagrams/live-validation-ladder.mmd](diagrams/live-validation-ladder.mmd)

## Live Campaign Profiles

![Live campaign profiles image](images/documentation-suite-2026-05-11/live-campaign-profiles.png)

```mermaid
flowchart LR
    QUICK["Quick<br/>30 seed users<br/>3 CRUD samples per region"]
    STANDARD["Standard<br/>300 seed users<br/>10 CRUD samples per region"]
    FULL["Full<br/>3,000 seed users<br/>100 CRUD samples per region<br/>default"]
    HARNESS["Live campaign harness<br/>snapshot<br/>seed reconcile<br/>CSV ingestion<br/>projection<br/>CRUD validation"]
    SUMMARY["campaign-summary.json<br/>profile-derived totals"]

    QUICK --> HARNESS
    STANDARD --> HARNESS
    FULL --> HARNESS
    HARNESS --> SUMMARY
```

Source file: [diagrams/live-campaign-profiles.mmd](diagrams/live-campaign-profiles.mmd)

## Release Readiness

![Release readiness image](images/documentation-suite-2026-05-11/release-readiness.png)

```mermaid
flowchart LR
    INPUTS["Inputs<br/>DrunkenAD.psd1<br/>DrunkenAD.psm1<br/>Public commands<br/>Private helpers<br/>docs<br/>tests"]
    SCRIPT["scripts/Test-DrunkenADRelease.ps1"]
    CHECKS["Release gate<br/>manifest metadata<br/>clean import<br/>export parity<br/>syntax<br/>docs hygiene<br/>unit tests"]
    CI["CI acceptance<br/>Ubuntu<br/>macOS<br/>Windows<br/>no PSGallery publish"]

    INPUTS --> SCRIPT
    SCRIPT --> CHECKS
    CHECKS --> CI
```

Source file: [diagrams/release-readiness-flow.mmd](diagrams/release-readiness-flow.mmd)
