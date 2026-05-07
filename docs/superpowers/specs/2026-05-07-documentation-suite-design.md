# DrunkenAD Documentation Suite Design

## Purpose

Build a complete operator-facing documentation suite for DrunkenAD that explains
why the module exists, when to use it, how data flows through `drink`, how to
operate it safely, and how to reproduce the live WinServer validation.

## Audience

- Directory engineers evaluating `drink` as a small user-attached data store.
- Operators running CSV ingestion, projection, and namespace maintenance.
- Reviewers who need proof that the module has been exercised against a live AD
  lab and that schema readiness is handled explicitly.

## Documentation Structure

The suite should keep the README concise and move deeper material into focused
docs:

- `docs/README.md`: documentation index and reading paths.
- `docs/USE-CASES.md`: concrete use cases, anti-use-cases, and namespace
  examples.
- `docs/ARCHITECTURE.md`: conceptual model, command boundaries, and data flow.
- `docs/OPERATIONS.md`: operator runbook for readiness checks, write safety,
  CSV ingestion, projection, and rollback expectations.
- `docs/DIAGRAMS.md`: Mermaid source for the diagrams used across the suite.
- Existing focused pages remain canonical for their domains:
  `DATA-STORE.md`, `HOW-TO-INGEST-CSV.md`, `SCHEMA-ENABLEMENT.md`,
  `TESTING.md`, `LIVE-VALIDATION.md`, and the dated WinServer run note.

## Mermaid Diagrams

Create editable Mermaid source for these views:

1. Use-case map: source systems, namespace categories, and consumers.
2. Namespace write model: read current values, replace owned prefixes, preserve
   unrelated prefixes, commit to AD.
3. CSV ingestion flow: CSV plus mapping config into `Import-ADUserDrinkCsvData`
   and read-back validation.
4. Schema readiness flow: schema presence versus user-class write readiness.
5. Live validation ladder: parser/unit, integration, smoke, seed, CSV,
   projection, CRUD.

Mermaid remains the source of truth for diagrams. Raster images are generated
infographic plates that make the same ideas easy to scan in rendered docs; they
do not replace the editable diagram source.

## Page Images

Each new major page should have one no-nonsense, elegant generated infographic
plate:

- Clean documentary/product style.
- No fantasy, mascots, fake brand marks, or decorative filler.
- Use readable labels, concrete AD object examples, sample `drink` values, and
  workflow arrows when they clarify the page.
- The visual structure should match the page purpose: operator console,
  directory records, flow boards, schema gate, or validation evidence.
- Images live under `docs/images/documentation-suite-2026-05-07/` with stable
  filenames.
- Every image should be referenced from a Markdown page and should have a nearby
  prompt note so future maintainers can regenerate or revise it.

## Commit Plan

Use staged commits:

1. Live-validation evidence checkpoint.
2. Documentation-suite design checkpoint.
3. Documentation pages and Mermaid diagrams.
4. Generated page images and image prompt manifest.
5. Final verification cleanup if needed.

## Validation

Before pushing:

- Run `git diff --check`.
- Check all Markdown links that target local repo files.
- Confirm image files exist and are referenced by docs.
- Confirm no ignored live credential files are staged.
- Review the Git history to ensure commits are logically staged.
