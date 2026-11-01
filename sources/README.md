# Sources and release selection

`dataset_selection.json` decides which publisher releases enter the pipeline. It has
one `true`/`false` switch per publication and release. The catalogues it pins list
every known source file.

```
sources/dataset_selection.json ─┐
sources/catalogues/*.csv (pinned)┴─> get_source_data.R ─> source_metadata.csv ─> targets: select_sheets() ─> data ─> …
                                      (outside targets)    + preparation_report.csv
```

## Adding a release

1. Change its switch to `true` in `dataset_selection.json` (`releases` → publication →
   release key).
2. `Rscript get_source_data.R`. It does three things:
   - downloads the release's workbooks and checks each against its pinned
     `source_sha256`;
   - copies XLSX files and converts XLS/XLSM with Microsoft Excel;
   - rewrites `source_metadata.csv`.

   Check `sources/preparation_report.csv`. Anything not `prepared` (unsupported format,
   failed download, SHA mismatch, failed conversion) is not admitted.
3. `Rscript agents/queue.R build`, then run the agents. Only switched-on releases are
   queued, and their new sheets need recipes.
4. Run `targets::tar_make()`.
   - `tar_read(selection_coverage)` shows sheets and recipes per switched-on release.
   - `tar_read(selected_sheets_checks)` warns about switched-on releases with no
     prepared sheets or with missing recipes.
   - New releases may also need entries in the normalisation, harmonisation and
     measure specs. The checks report new title subjects and unmapped labels.

Switching a release to `false` removes its sheets from the pipeline at the next
`tar_make()`. Nothing is deleted, and other releases' branches are not rebuilt.

**What reruns.** Each sheet's branches depend only on its recipe and a few fields of its
metadata row (see `recipe_sheets` in `_targets.R`). So:
- rewriting `source_metadata.csv`, even with new provenance columns on every row,
  rebuilds no sheet branches;
- new sheets get new branches;
- the whole-table stages (assemble through the CSVs) rerun when any sheet changes,
  about 6 minutes.

## The selection file

- **`releases`:** the only part to edit. Unlisted releases are excluded; nothing is
  chosen automatically by date or "latest".
- **Release keys:** `source_release_id` without the `"<publication_id>::"` prefix (e.g.
  `2023-24-complete`, `rogs-2026`, `snapshot-2026-11-01`). Where that ID is missing,
  `asset_year`, written `YYYY-YY` for fiscal-year publications. A snapshot key names
  a checked catalogue snapshot, not necessarily the period covered.
- **`_catalogues`:** each catalogue's path (relative to this file), its SHA-256 pin and
  `include_rows`. In `include_rows`, values within a column are alternatives (OR), and
  different columns must all match (AND).

  `get_source_data.R` stops if a catalogue no longer matches its pin. Review the change,
  then update the pin deliberately; pins are never refreshed automatically.
- **Checks:** `get_source_data.R` also stops on duplicate keys, a switch that isn't
  `true`/`false`, a row without a release key, or a switched-on release with no
  eligible catalogue rows.

## Catalogues (`catalogues/`)

Byte-identical copies of the inventories handed over on 2026-11-01 (from
`../tidy-pipeline-to-integrate/`):

| Catalogue | Contents | Rows that can be admitted |
|---|---|---|
| `current_pipeline.csv` | The sheet-level inventory of the original package, with publisher URL fields: 5,118 sheets, 545 active workbooks | `reference_only == FALSE`. Archived copies stay in `source_metadata.csv` for lineage |
| `national_additions.csv` | 886 workbook records: missing releases of the ABS series, Recorded Crime—Victims, Crime Victimisation, and related ABS, AIHW, AIC and PC publications | All rows |
| `state_crime.csv` | 1,308 state and territory resources | `verification_status == download_verified` and `resource_role` in `data`, `statistical_report` (1,104 rows; 628 XLSX, 339 PDF, 124 CSV, 7 XLS, 3 XLSM, 3 ZIP) |

These are catalogues, not data. Only XLSX, XLS and XLSM files can be prepared. PDF, CSV,
ZIP files without a named member, and Word files are reported as `unsupported_format`,
because they would need their own readers.

`state_crime.csv` keeps geography fields (`geography_levels`, `geographic_area`,
`regional_data`, `time_coverage`, …). They're carried into `source_metadata.csv` for
prepared files. `regional_data == not_confirmed` doesn't establish regional coverage.

## Identities and provenance

- `source_sha256` identifies the original publisher bytes (for ZIP downloads, the named
  archive member), and `xlsx_sha256` the XLSX the pipeline reads.
- `sheet_key = source_sha256 + "/" + exact sheet name`, and `sheet_sha256 =
  SHA-256(sheet_key)`. Recipes are `tidy-recipes/<sheet_sha256>.json`. Sheet names are
  never trimmed.
- **Where prepared files go:**
  - originals in `source-originals/<source_sha256>--<file name>`;
  - XLSX in `source-spreadsheets-xlsx/<source_sha256>--<file name>.xlsx`, as for the
    original package.
- **Duplicates:** source files are deduplicated on `(publication_id, source_sha256)`;
  a current-pipeline row wins.
- **Mismatches:** a download that doesn't match its pin is reported as `sha256_mismatch`
  and not used. For example, the AIHW Child protection 2024–25 workbook was corrected
  by the publisher on 21 October 2026 (`Table 4.6!K61`, 108 → 107). The retained
  version keeps its identity (`source_url_match == publisher_revision`). A revised
  download is a new version to review and catalogue.
- **Provenance fields:** every catalogue field is kept in `source_metadata.csv`: URLs,
  archive members, formats, byte lengths, verification notes and dates. The `catalogue`
  column says which catalogue a row came from.

## Converting XLS and XLSM

`convert_with_excel.applescript` uses Microsoft Excel the way the original package was
converted: Excel XML format (51), links not updated, manual calculation and no
recalculation before saving. Macros are not run, and they are dropped by the XLSX
format. The conversion runs inside Excel's sandbox container, so Excel needs no
file-access prompt.

The script only saves and closes the workbook it opened, by name. It never touches a
workbook you have open. The first run may ask permission for Terminal to control Excel.

**Tested 2026-11-01** in a scratch copy, with three releases: `childhood-abuse/2021-22`
(XLSX), `criminal-courts-australia/2002-03` (an Excel 95 XLS) and
`federal-defendants-australia/2010-11` (four XLS inside ZIP archives).
- All six downloads matched their pinned SHA-256.
- Conversion took a few seconds per file.
- A cell-by-cell comparison of a converted workbook with the original (read by
  `readxl`) found identical values and sheet names. The XLSX keeps trailing spaces and
  space-only cells, which `readxl` trims.

If Excel shows a dialog (e.g. after an interrupted run), it ignores automation until
the dialog is dismissed. Conversions then report `conversion_failed`; close the dialog
and rerun. After three failures in a row the script stops converting. Only one run of
`get_source_data.R` at a time.

**Macro workbooks.** Excel asks before opening any workbook with macros, whatever the
automation settings. The script therefore detects them first (an XLS containing a VBA
project, or any XLSM) and reports them as `has_macros`. To convert them:
1. set Excel ▸ Settings ▸ Security to "Disable all macros without notification";
2. run `EXCEL_MACROS_DISABLED=1 Rscript get_source_data.R`;
3. set Excel back.

Macros are never run, as in the original package's conversions.

**Excel settings.** The script records Excel's "ask to update links" and automation
security before converting and restores them afterwards. If Excel is blocked by a
dialog at that point, it prints the values to restore.

**Short names inside the container.** Excel can't save to paths longer than 218
characters, so files are named by `source_sha256` inside Excel's container and get
their full names when copied out.

**First full run (2026-11-01).** All releases of the four ABS justice publications:
- 258 workbooks downloaded and SHA-checked;
- 241 XLS converted, 50 of them macro workbooks;
- 1,932 new sheets.

A cell-by-cell check of 12 converted workbooks (6 with macros) found all 47,173 values
identical to the originals, apart from line breaks inside 6 header cells (`\r\n` in
the XLSX, read as `\n` from the XLS) and whitespace in one note.

**Second run (2026-11-01/02).** All releases of the two ABS victims publications:
- 396 workbooks prepared, 68 of them macro workbooks, giving 3,831 sheets;
- one 2015 Recorded Crime – Victims file came only from `source_url`: its
  `download_url` now answers "Attachment Not Found".

**Download URLs.** The script tries `download_url`, then `source_url`, and keeps the
first whose bytes match the pin. The two differ for 627 of the 886 national files.

`build_current_catalogue.R` is history only. It built the first version of
`current_pipeline.csv` from the original package metadata.
