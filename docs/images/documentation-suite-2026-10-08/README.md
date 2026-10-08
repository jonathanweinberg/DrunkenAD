# Illustrated Documentation Refresh

The owner requested the original imagegen visual style back on the main page,
with current technical content and Mermaid retained in the detailed docs.
These seven 1536 x 1024 PNGs were generated with the built-in imagegen tool from
the v0.13.1 style references, then visually inspected. Historical files were
not overwritten. No image is a claim of successful testing or publication.

| Asset | Exact Prompt And Provenance | Technical Detail |
| --- | --- | --- |
| [Module layout](module-layout.png) | [Prompt](module-layout-prompt.md) | [Architecture](../../ARCHITECTURE.md) |
| [Namespace writes](namespace-write-model.png) | [Prompt](namespace-write-model-prompt.md) | [Data model](../../DATA-STORE.md) |
| [CSV ingestion](csv-ingestion-flow.png) | [Prompt](csv-ingestion-flow-prompt.md) | [CSV guide](../../HOW-TO-INGEST-CSV.md) |
| [Schema readiness](schema-readiness-flow.png) | [Prompt](schema-readiness-flow-prompt.md) | [Schema guide](../../SCHEMA-ENABLEMENT.md) |
| [Live validation](live-validation-ladder.png) | [Prompt](live-validation-ladder-prompt.md) | [Testing](../../TESTING.md) |
| [Campaign profiles](live-campaign-profiles.png) | [Prompt](live-campaign-profiles-prompt.md) | [Live guide](../../LIVE-VALIDATION.md) |
| [Release readiness](release-readiness.png) | [Prompt](release-readiness-prompt.md) | [Release gate](../../TESTING.md#release-readiness-gate) |

Content checks covered prefix isolation, Remove/Add-only writes, CSV blank
retention and strict decoding, computed-output caveats, inherited/auxiliary
schema checks, explicit mutation approval, cleanup, profile counts, and
separate publication approval. Source behavior and Markdown remain authoritative
when an illustration uses shortened labels.

The images are project documentation assets covered by the repository's
BSD 3-Clause License.
