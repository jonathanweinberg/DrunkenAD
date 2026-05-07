# Documentation Suite Image Prompts

These images were generated with the built-in image generation tool and copied
from the Codex generated-image cache into this repo. The Mermaid files in
`docs/diagrams/` remain the editable diagram source of truth. These PNG files
are page-facing infographic plates with labels, sample values, and workflow
context.

## drunkenad-overview.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and amber palette. Title: "DrunkenAD". Subtitle: "Active Directory drink attribute as a namespaced data store". Tagline: "Store. Organize. Automate. Validate." Center: a large Active Directory User Object card for Alice Bennett with sAMAccountName, userPrincipalName, objectClass, and a highlighted "drink (multivalue attribute)" panel containing exact sample values: Flags-Enabled, Tenant-Id=TEN-NA-0001, Routing-mail=alice.bennett.na0001@lab.contoso.com, Sync-State=Ready, Keep-Stable. Left side workflow cards numbered 1 to 3: Schema readiness, CSV ingestion, Attribute projection. Right side workflow cards numbered 4 to 5: Namespace updates, Live validation, plus a Validation & Reporting card. Bottom strip: Compact, Namespaced, Safe & Controlled, Replicates, Observable. Use precise arrows, realistic UI cards, readable labels, no mascots, no fantasy, no fake logos.
```

## use-case-map.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and amber palette. Title: "DrunkenAD Use Cases". Subtitle: "Small user-attached metadata that travels with the AD object". Center: a large Active Directory user drink attribute card for Alice Bennett showing sAMAccountName, userPrincipalName, objectClass, distinguishedName, and highlighted "drink (multivalue attribute)" values: Flags-Enabled, Profile-Tier=Gold, Routing-Mailbox=alice.bennett.na0001@lab.contoso.com, Tenant-Id=TEN-NA-0001, Sync-State=Ready. Left source cards numbered 1 to 4: HR export, IAM workflow, Application config, Sync engine. Right consumer cards numbered 5 to 8: Provisioning, Mail routing, Audit review, Internal apps. Bottom strip: Feature flags, Tenant markers, Routing hints, Sync metadata, Attribute projection, plus a small "Poor fits" box listing secrets or credentials, large JSON documents, audit logs or narratives, high-frequency counters. Use clear arrows, readable labels, realistic documentation UI, no mascots, no fantasy, no fake logos.
```

## namespace-write-model.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and amber palette. Title: "Namespace Write Model". Subtitle: "Replace owned prefixes, preserve everything else". Top row five numbered steps: Read current drink values, Identify owned prefixes, Remove matching old values, Add replacement values, Commit final multivalue attribute. Middle layout: Before current drink values list with Profile-Tier=Silver and Routing-mail=old@example.com marked OWNED, Flags-Enabled and Keep-Stable marked KEEP. Center filter/update box with owned prefixes Profile- and Routing-. After final values list with Profile-Tier=Gold, Flags-Enabled, Routing-mail=alice.bennett.na0001@lab.contoso.com, Keep-Stable. Include callouts: literal prefixes, safe update, empty result, PassThru. Bottom strip: Exact lookup, Literal matching, Prefix ownership, AD replication, Audit-friendly. Use readable labels, exact sample values, precise arrows, no mascots, no fantasy, no fake logos.
```

## csv-ingestion-flow.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and amber palette. Title: "CSV Ingestion". Subtitle: "Turn flat files into namespaced drink records". Three large columns with arrows: 1 CSV Source, 2 Mapping Configuration, 3 Active Directory User Object. CSV table columns: SamAccountName, ProfileTier, ProfileRegion, Flags, RoutingMailbox, TenantId, SyncState, with a sample alice.bennett row. Mapping table columns: Namespace Prefix, CSV Column, Key Template, Multivalue, Required; include Profile-, Flags-, Routing-, Tenant-, Sync-. Output user object for Alice Bennett with drink values: Profile-Tier=Gold, Profile-Region=NA, Flags-Enabled, Flags-Audited, Routing-Mailbox=alice.bennett.na0001@lab.contoso.com, Tenant-Id=TEN-NA-0001, Sync-State=Ready. Include format guidelines, validation checkpoints, and bottom benefit strip: Config-driven, Idempotent, Prefix-owned, Previewable, Reportable. Use readable labels, realistic table UI, no mascots, no fantasy, no fake logos.
```

## schema-readiness-flow.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, green, and red palette. Title: "Schema Readiness". Subtitle: "Attribute presence is not the same as user write readiness". Top row five numbered checks: Resolve schema naming context, Find attributeSchema LDAPDisplayName=drink, Confirm isDefunct is false, Confirm user class mayContain includes drink, Refresh schema cache and validate a write probe. Left red panel "Not ready states": AttributeMissing, AttributeDefunct, NotAllowedOnUserClass. Center panel "Active Directory schema objects" with attributeSchema object fields LDAPDisplayName drink, isMultiValued TRUE, isDefunct FALSE, and ClassSchema object CN=User with mayContain excerpt including drink. Right green panel "Ready state" with ReadyForUserWrite=True and AllowedOnUserClass=True. Bottom strip: Snapshot first, Schema master only, Explicit expectations, Cache refresh, Write probe. Use readable labels, exact field names, no mascots, no fantasy, no fake logos.
```

## live-validation-ladder.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and green palette. Title: "Live Validation Ladder". Subtitle: "Prove the module against a real AD lab before trusting writes". Show a two-row ladder with numbered cards 1 to 10 connected by arrows: Snapshot or rollback point, Parser gate, Unit tests, Live integration tests, Smoke validation, Seed reconcile, CSV ingestion, Attribute projection, CRUD sample validation, campaign-summary.json. Right side required services checklist: SSH, WinRM, SMB, DNS, ADWS, Kdc, Netlogon, NTDS. Bottom evidence panel titled "Campaign Evidence (final)" for WinServer.lab.contoso.com with run ID, captured timestamp, Passed status, seed users 3000, CSV processed 3000, projection processed 3000, CRUD processed 300, failures 0. Include artifacts produced: campaign-summary.json, ValidationReport.html, Evidence screenshots, PowerShell transcripts, Error log if any. Bottom strip: Reproducible, Credential-safe, Snapshot-backed, Reported, Screenshot evidence. Use readable labels, exact evidence values, no mascots, no fantasy, no fake logos.
```
