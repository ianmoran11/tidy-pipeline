# Reference-only copies

These 76 workbooks duplicate an active workbook in `source-spreadsheets-xlsx/`.
They are kept for reference and provenance only. Do not write recipes for them;
write the recipe for the active workbook's sheet instead.

`reference-only.csv` lists each file with:

| Column | Meaning |
|---|---|
| `copy_type` | `normalised copy` (made by the earlier pipeline) or `archive duplicate` (the same workbook taken from the publisher's combined archive) |
| `normalization` | The recorded normalisation, for normalised copies |
| `active_xlsx_file`, `active_sha256` | The publisher workbook this file duplicates |
| `differences` | How it differs from the active workbook, from a cell-by-cell comparison |
| `database_references` | How `tidy-data-asset-status.sqlite3` refers to this file |

## How they differ from the active workbooks

Every copy has the same sheets, sheet names and cell addresses as its active
workbook. Compared cell by cell:

- 66 normalised copies and the 3 archive duplicates have the same non-blank
  cells and values; only formatting differs.
- 2 normalised copies drop junk: a footnote or `na` repeated along a whole row
  out to column XFD (32,734 and 16,373 cells).
- 4 drop stray cells or check merged cells, as recorded in their corrections.
- 1 changes a value: Criminal Courts 2021–22 cube 11, Table 51 `M5`, the
  impossible period header `2022–22` corrected to `2021–22`. The active
  workbook keeps the published `2022–22`.

The database's accepted data mostly refers to the normalised copies, so their
`sha256` values appear in `asset.source_digest`. The active workbooks hold the
same cells at the same addresses.

## How the project treats them

- `source_metadata.csv` keeps their sheets, with `reference_only = TRUE`,
  `xlsx_path` pointing here, and `active_sheet_sha256` giving the matching sheet
  of the active workbook.
- `agents/queue.R` does not queue them, and the recipe validator rejects recipes
  for them.
- The recipe tools can still show them (`sheet_grid`, `list_workbook_sheets`).

`CHECKSUMS.sha256` in the parent folder lists them at `reference-only/<file>`.
The parent `README.md`, `conversion-map.csv` and `conversion-manifest.json` are
unchanged and still describe the package as converted.
