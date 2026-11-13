# Excel CSV Validation Intake

Status: source input prepared; authentic Excel exports and live import remain
unproven. This protocol supplies case 13 of the
[post-merge matrix](POST-MERGE-VALIDATION.md). It is not permission to create
directory objects, import data, install Excel, or publish a release.

## Source Workbook

Use one worksheet named `Export`, with exactly `A1:B3` populated. The first row
contains `SamAccountName` and `Payload`. The following JSON specifies every
cell, including literal Unicode characters and embedded newline sequences.
Decode JSON escapes into cell text; do not enter the escape spellings in Excel.
All cells are strings, not formulas. The identities are invented and must not
be matched to existing accounts.

```json
{
  "sheet": "Export",
  "cells": [
    ["SamAccountName", "Payload"],
    ["excel-caf\u00e9", "Caf\u00e9, \"Gold\"\nLine two: M\u00fcnchen"],
    ["excel-demo-b", "Cr\u00e8me, \"Silver\"\r\nLine two: Z\u00fcrich"]
  ]
}
```

The source workbook supplied with this review is generated test input, **not
an Excel-produced CSV**. Its cells must be checked against this specification
after saving and before exporting. Formatting stays within the data range;
no cover sheet, instructions, totals, or extra header rows belong in the CSV.
The first payload has one LF; the second has one CR followed by one LF. Record
any changes Excel makes instead of silently normalizing the expectations.

## Original Exports

From an existing Excel installation, open the unchanged source workbook and
export the `Export` sheet twice to separate files:

1. Excel's CSV UTF-8 save format.
2. Excel's plain CSV save format, such as CSV (Comma delimited).

Keep both original files byte-for-byte, including any BOM, delimiters, quotes,
and line endings. Record warnings and whether Excel altered the workbook or
cell contents. Do not reopen and resave a CSV, transcode it, or substitute an
export from another application. A Mac export cannot establish the behavior
of Windows Excel; preserve that environment distinction.

For each file, retain this provenance alongside the private receipt:

| Field | Required Evidence |
| --- | --- |
| Exporter | Excel product, version/build, operating system and version. |
| Regional settings | Locale, configured list separator, relevant Excel separator settings. |
| Save operation | Exact save-format label, original workbook hash, export time, observed warnings. |
| Original bytes | CSV SHA-256, byte length, observed BOM and delimiter, record and embedded-cell newline forms. |
| Logical cells | Two data records, two exact header names, and ordinal comparison of each decoded cell to the specification. |
| Candidate | Module commit/tree or file hashes and the PowerShell runtime used for intake. |

Do not include passwords, real account information, customer exports, private
workstation paths, or directory endpoints in public evidence. These synthetic
CSVs may become checked-in fixtures only after provenance and privacy review.

## Offline Acceptance

The existing [CSV tests](../tests/DrunkenAD.Unit.Tests.ps1) establish the strict
decoder contract using constructed byte fixtures. They do not establish Excel
export behavior. Use the original Excel files to add these distinct checks:

1. Inspect bytes before decoding. A filename or save-format label does not
   prove an encoding. Check comma separation against the importer's contract;
   classify an observed semicolon-separated file separately, without editing
   it into a purported original comma-separated export.
2. Run the private CSV reader in module scope with no directory calls. For a
   supported Unicode encoding, compare the parsed header, record count and
   all cells ordinally to the workbook specification. An embedded newline
   must not create another logical record, and doubled CSV quotes must decode
   to the original literal quotes.
3. Exercise the public importer only inside the existing mocked test harness.
   Use `ExcelProbe-` mapped directly to `Payload`, with no `Label` or `SplitOn`.
   Assert the exact prefixed payloads and identities reaching the modeled
   operations, with unrelated values preserved. This is not live AD proof.
4. When original bytes violate the supported encoding contract, require a
   decoding error before context creation, schema checks, user reads or writes.
   Never make a file pass by transcoding it before this assertion.
5. Compare accepted text to the source cells even when decoding succeeds.
   Exporter-side substitution or newline conversion is a distinct mismatch,
   not proof of a decoder defect. Preserve it in the receipt and decide the
   supported exporter workflow explicitly.

Plain CSV is not rejected just for its format name. For example, ASCII is valid
UTF-8, while a Windows-1252 accented byte sequence may be invalid UTF-8. Valid
encoded U+FFFD remains legal input. Keep synthetic invalid-byte, UTF-16/32 and
BOM variants separate from authentic exporter evidence. Any derived variant
must be labeled with its transformation and original source hash.

`Import-ADUserDrinkCsvData -WhatIf` is **not an offline check**: valid input can
reach schema and user reads. Do not use it to bypass the mocked harness or the
live approval boundary.

## Live Acceptance And Current Gaps

After offline intake succeeds, a separately authorized run must bind these
synthetic identities to owned disabled fixtures, check the selected DC and
rollback prerequisite, import the original supported file, and compare fresh
read-back of the complete value set to the original cells. Verify unrelated
namespace preservation, then remove only owned fixtures and verify absence.
Original unsupported bytes must fail before directory access. Retain counts,
candidate hashes and sanitized outcomes, not raw lab exports.

No original Excel CSV pair has been received or validated in this review.
There is no new live allowance for this protocol. Source-workbook creation,
mocked parser success, or unrelated Export-Csv live coverage cannot mark
case 13 passed. Release/tagging and issue closure remain separate owner
decisions.
