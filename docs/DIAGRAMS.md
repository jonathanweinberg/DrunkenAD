# DrunkenAD Diagrams

This page keeps the Mermaid diagrams and their generated infographic plates
together. The Mermaid files under `docs/diagrams/` are the editable source of
truth. The PNG images under `docs/images/documentation-suite-2026-05-07/` are
page-facing explanations with labels, examples, and workflow context.

## Product Overview

![DrunkenAD overview image](images/documentation-suite-2026-05-07/drunkenad-overview.png)

Use this image when introducing the whole project: schema readiness, CSV
ingestion, projection, namespace updates, live validation, and reporting all
around the same `drink` attribute model.

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
