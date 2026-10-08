# DrunkenAD Use Cases

DrunkenAD is useful when a compact amount of application state should travel
with the AD user object and be readable by normal directory-aware tooling. It is
not a general database, policy engine, or document store.

![Use-case map](images/documentation-suite-2026-05-07/use-case-map.png)

The source diagram for this page lives at
[diagrams/use-case-map.mmd](diagrams/use-case-map.mmd).

## Good Fits

### Feature Flags

Use `Flags-` records when internal tooling needs small, explicit markers that
follow the user:

```text
Flags-Enabled
Flags-Audited
Flags-RemoteEligible
```

This is best for coarse-grained state. It is not a replacement for a policy
system or feature service that needs complex targeting rules.

### Tenant And Environment Markers

Use `Tenant-` or `Env-` records when downstream provisioning, sync, or routing
tools need a stable scope marker:

```text
Tenant-Id=TEN-NA-0001
Env-Name=Lab
```

Keep the payload short and deterministic. If the value needs nested structure,
store an identifier and let the consumer resolve the richer data elsewhere.

### Application Routing Hints

Use `AppRouting-` records for compact delivery hints, separate from the built-in
projection's `Routing-` namespace:

```text
AppRouting-Mailbox=alice.bennett.na0001@lab.contoso.com
AppRouting-Queue=identity-review
```

Routing records work best when they are inputs to another system, not a full
copy of that system's configuration.

### Lightweight Sync Metadata

Use `Sync-` records for import state, handoff state, or reconciliation hints:

```text
Sync-State=Ready
Sync-LastSource=HRSeed
```

These values are especially useful when the next hop can read AD but does not
share a central application database.

### Attribute Projection

Use `Set-ADUserDrinkProjection` when a consumer needs a normalized view of
existing AD user attributes without deciding how to query every source field:

```text
Identity-userPrincipalName=alice.bennett.na0001@lab.contoso.com
Meta-employeeID=100001
Profile-samAccountName=abennettna0001
```

Projection is repeatable and namespace-scoped. It is a good fit for operational
snapshots and compatibility bridges.

## Poor Fits

Avoid DrunkenAD when the data is large, sensitive, highly relational, frequently
rewritten by many writers, or needs transactional behavior across objects.

Examples that should live somewhere else:

- access tokens, passwords, or shared secrets
- large JSON documents
- audit logs
- policy decisions with many conditions
- high-frequency counters
- records that need foreign keys, joins, or retention policies

## Namespace Ownership

Before a workflow writes data, decide which prefixes it owns. A workflow that
owns `AppProfile-` can replace all `AppProfile-...` records, so another workflow
should not also treat that same prefix as its private space.

Good ownership boundaries:

| Owner | Prefixes |
| --- | --- |
| Application metadata | `AppProfile-`, `AppRouting-`, `AppMeta-` |
| Sample CSV ingestion | `CsvProfile-`, `Flags-`, `CsvRouting-`, `Tenant-`, `Sync-` |
| Default AD projection | `Profile-`, `Identity-`, `Meta-`, `Routing-`, `Notify-` |
| CRUD validation | `Keep-`, `Scenario-`, `Literal[01]-` |

Shared prefixes are allowed, but they should be deliberate and documented.
The shipped sample and default projection use disjoint prefixes and can run in
either order. Custom maps must preserve that separation themselves.
