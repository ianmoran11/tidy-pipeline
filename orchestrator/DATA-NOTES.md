# Data notes

Facts about the source spreadsheets and the reference database that took effort to
establish.

## Catalogues and selection (`sources/`)

Since 2026-11-01, admission is by release switches in `sources/dataset_selection.json`.
Three pinned catalogues list the known sources:
- the current package;
- 886 national workbook records;
- 1,308 state and territory resources.

There are 721 switches across 99 publications; 59 were on at handoff, covering all
3,256 recipes. `sources/README.md` covers release keys, filters, identities and the
known AIHW 2024–25 publisher revision. Test downloads of ABS URLs worked, including
`AUSSTATS/subscriber.nsf/log?openagent&…zip` archives. The two 2010–11 Federal
Defendants archives each contain a member named `45150do003_201011.xls`; their bytes
and SHAs differ.

## Victims publications (admitted 2026-11-01/02)

**Crime Victimisation, Australia** (ABS 4530.0, a household survey; 17 releases,
2008–09 to 2024–25, 175 workbooks, 2,501 sheets):
- **Estimates and RSEs.** Each estimate table has relative standard error (RSE)
  companions. From about 2010–11 these are separate sheets ("Table 5a … : Relative
  standard error"; letters a/b/c/d). Older releases put "RSE OF …" blocks beside the
  estimates. Both end up in `estimate_type`.
- **Asterisks from number formats.** Estimates with high RSEs are marked `*` (RSE
  25–50%) and `**` (over 50%), mostly by the number format, not the cell text.
- **Population.** Persons aged 15 and over; sexual assault is asked of people aged 18
  and over. Household crimes count households.
- **Pooled periods.** Some tables pool two years ("2019–21" = 2019–20 and 2020–21).
- **Upper-case labels** in older releases, normalised to sentence case.

**Recorded Crime – Victims** (ABS 4510.0, police records; 22 releases, 2004 to 2025,
221 workbooks, 1,330 sheets):
- **Calendar years** (reference date 31 December).
- **Age basis.** Tables give age "at incident" or "at report", often only in the title.
- **Family and domestic violence tables** cover offences that are FDV-related, which
  becomes `scope`.
- **Revisions.** Earlier releases' values for the same series and period are often
  revised: 88.8% equal to the latest release, 96% within 5%. 2005–2013 releases agree
  least, with a median ratio of 1.00.
- **Title quirks:** a 2008 table titled "…Australia–2007 revised" holds revised 2007
  figures, and one title spells "Queeensland".

**Title quirk (all publications).** Some titles have no space after the table number
("Table 6PERSONS AGED…"). The measure spec's subject pattern takes a table letter only
in lower case, so the subject keeps its first letter.

## Source package (`source-spreadsheets-xlsx/`)

- 621 XLSX workbooks converted from the original package: 311 XLS files converted by
  Excel, 310 XLSX copied byte for byte. Each file name starts with the **original**
  file's SHA-256, not the converted file's. Conversion details: `README.md`,
  `conversion-map.csv`, `conversion-manifest.json`.
- `original-package-metadata/` describes the original package: `manifest.json` (files,
  database references, 73 normalisation relationships), `database-references.csv`
  (every direct database reference to a workbook), `NOTICE.md` (attribution and
  release caveats).
- **Active vs reference-only.** 545 workbooks are active. 76 are archived in
  `reference-only/`:
  - 73 normalised copies made by the earlier pipeline;
  - 3 `archive-member` workbooks that duplicate their `-source` workbook.

  A cell-by-cell comparison found the copies keep every sheet and value. They differ
  only in removed junk (49,107 cells of a footnote repeated to column XFD in
  Offenders 2023–24 cubes 2 and 3), 4 stray cells, and one header correction (Courts
  2021–22 cube 11 Table 51 `M5`: `2022–22` → `2021–22`). Details per file:
  `reference-only/reference-only.csv`.
- **Other overlaps** are boilerplate only: 105 workbook pairs share contents or
  explanatory-notes sheets.
- **Awkward sheets.** Ten sheet names end in a space. Original Offenders 2023–24
  cube 2 Table 6 and 15, and cube 3 Table 21, have a footnote repeated across a row to
  column XFD (`sheet_grid` collapses runs of 20+ identical cells). A few originals
  have stray numbers outside tables (e.g. Offenders 2024–25 Table 4 `XFC50 = 3`);
  agents keep these as `annotations`.

## `source_metadata.csv` (from `get_source_data.R`)

One row per sheet (5,118). Key columns:
- `sheet_sha256`, `sheet_key`, `sheet` / `sheets` (exact name), `sheet_index`
  (tab position; do not pass to tidyxl);
- `xlsx_path`, `xlsx_file`, `source_sha256` (original file), `xlsx_sha256`;
- `publication_id`, `publication`, `publisher`, `period_format`;
- `source_release_id`, `release`, `reference_period`, `reference_date`,
  `release_date` (historical "source-only" releases);
- `asset_year`, `asset_reference_date`, `cohort_ids` (accepted 2020+ releases);
- `normalization`, `normalized_from_sha256`, `normalized_to_sha256`;
- `reference_only`, `reference_copy_type`, `active_sha256`, `active_sheet_sha256`.

Read it with `readr::read_csv(..., trim_ws = FALSE)`.

## Publications

| Publication | Publisher | Notes |
|---|---|---|
| criminal-courts-australia | ABS | Many state- and court-level tables whose state and court level are only in the title |
| recorded-crime-offenders | ABS | Several sheets per cube by state ("–Queensland–2008–09 to 2010–11") |
| prisoners-australia | ABS | Census at 30 June: plain years mean 30 June. 2006–2008 releases are ~120 tiny workbooks |
| federal-defendants-australia | ABS | NUMBER / PROPORTION panels; year panels in older cubes |
| employee-earnings-hours-australia | ABS | May 2021/2023/2025; Table 2-style sheets are standard errors (title only) |
| aihw-child-protection-australia | AIHW | 2020–21 main workbook is 79 sheets; plain years mean 30 June |
| aihw-youth-justice-australia | AIHW | "Dec YYYY" periods; stray "-" rows below tables |
| pc-report-on-government-services-justice | Productivity Commission | Deep row outlines and a units column |

## Titles, subtitles, symbols and releases

Learnt while building the integration stages (2026-11-01).

**Title structure (ABS).** "Table N SUBJECT, breakdown, place, period", e.g. "Table 26
Defendants finalised, Summary characteristics by court level – Queensland, 2023–24".
- **Subject:** the text up to the first comma, usually who is counted. It's the only
  place that says "finalised" vs "with a guilty outcome", "sentenced" vs "unsentenced",
  or "offenders" vs "youth offenders".
- **Prefixes:** "FDV Table N", "ANZSOC 2023 Table N", and "Experimental data(a) –"
  (with a footnote marker).
- **Rate tables** name the measure in the subject ("CRUDE IMPRISONMENT RATE", "Offender
  rate").
- **Periods** usually follow ", " but sometimes a dash: "by age and sex–2009–10".
- **Court levels** appear as "– All Courts", "– Magistrates' Court" (singular) and
  "COMBINED ALL COURTS".
- **Federal Defendants Table 5** and Courts FDV tables 19–23 cover a single offence,
  named only in the title ("Harassment and threatening behaviour").

About 176 subjects map onto 52 populations (`measures/measure_spec.json`).

**Subtitles** hold the cube code and the release period: "45130DO004_201011 Criminal
Courts, Australia, 2010–11". The release period differs from the table period whenever
a release includes older tables.

**Criminal Courts 2009–10 and 2010–11 cubes** name their court level only through the
cube code. The data confirms this mapping (`qa/verify_court_cubes.R`):

| Cubes | Court level |
|---|---|
| 2 and 6 | Higher Courts |
| 3 and 7 | Magistrates' Courts |
| 4 and 8 | Children's Courts |
| 5 | all courts |

Neither the contents sheets nor the database name these court levels. Children's Courts
series start in 2006–07, the others in 2004–05 or 2005–06.

**Value symbols:** 12 spellings, all recognised (`integration/value_spec.json`).

| Publisher | Not published | Not available | Not applicable | Nil or rounded to zero |
|---|---|---|---|---|
| ABS (recent) | `np` | `na` | `..` | `–` (en dash) |
| ABS (older releases, 2001–2009) | `n.p.` | `n.a.`, `n.a` | `. .` | `-` (hyphen), `—` (em dash, older Prisoners), `  –  ` |
| AIHW | `n.p.`, `n.p` | `n.a.` | `. .` | `—` (em dash), `-` (one cell) |
| RoGS | `np` | `na` | `..` | `–` |

**Symbol meanings vary by workbook.** Recorded Crime 2019–20 to 2024–25 and two Prisoners
2025 workbooks define `na` as "not applicable"; most others mean "not available". The
meaning is read from each workbook's own legend into `value_spec.json` by
`qa/seeds/seed_value_legends.R` (33 workbooks). Rerun it after preparing new workbooks.

**Older Courts releases put the court level in places other than the title:**
- in the cube code (2008–09 to 2010–11);
- in the measure label ("NUMBER IN SUPREME COURT", "PROPORTION IN HIGHER COURTS (%)",
  2001–04);
- as combined levels ("Magistrates' & Children's Courts", Federal Defendants).

Older releases also pad labels with spaces and attach footnote markers, which the
normalisation `clean` rules remove.

**Blank cells.** EEH tables are sparse (occupation × method of setting pay), with
genuine published blanks: 17,056 of the 23,295 blank-cell records. The database
records blanks for ABS historical releases, including rows that are blank throughout,
but not for EEH.

**Statistic rows across rate panels.** A "Mean age" or "Median age" row runs across both
"Number" and "Offender rate" panels. Under the rate panel it's `na` or blank. After
splitting, both cells carry `measure = Mean age`. This is the harmless "number vs
symbol" conflict (ISSUES.md I26).

**Changing table shapes.** The same statistic changes table shape across releases. For
example, the Prisoners age-standardised imprisonment rate is by sex up to 2021 and has
no sex breakdown from 2022 (ISSUES.md I27).

**Population labels inside tables.** Combined Federal Defendants tables carry the
population as a column (eight spellings, e.g. "Finalised (excluding transfer to other
court levels)", "Guilty outcome"). The 2014–15 layout puts it in `measure` ("FEDERAL
DEFENDANTS FINALISED").

**Release identifiers.**

| Release type | `release_id` | `release_date` | Other date |
|---|---|---|---|
| Historical ("source-only") | `<publication>::<period>` | yes | |
| Accepted (2020+) | `<publication>-<asset_year>` | no | `asset_reference_date` |

Because the two types are dated differently, `reconcile()` orders releases by the
latest reference date in their own data. There are 59 releases among the sheets with
data.

## Reference database (`tidy-data-asset-status.sqlite3`, 9.4 GB, read-only)

| Table | Use |
|---|---|
| `source_publication`, `source_release` | Publication and release metadata (used by `get_source_data.R`) |
| `asset` | Accepted 2020+ data assets: `source_digest` (`sha256:<file sha>`), `sheet`, `year`, `reference_date`, `normalization` |
| `observation` | Accepted observations: `asset_id`, `source_cell`, `canonical_json`, raw value fields |
| `source_table`, `source_cell_observation` | Historical (source-only) releases, cell level |

- **Looking up cells:** `source_cell_observation` has a unique index on
  `(source_workbook_digest, source_sheet, source_cell)`. For `observation`, go through
  `asset.asset_id`; there is no index on digest.
- **Address formats:** `observation.source_cell` is R1C1 (`R31C2`) for most
  publications but A1 (`B12`) for Federal Defendants. EEH `source_cell_observation`
  uses R1C1.
- **Label formats:**
  - ABS historical: `row_dimensions_json` lists `{label, source_cell}`, and
    `semantic_json` has `column_heading_cells`, `observation_period`, `panel_label`.
    This gives an exact cell-level label comparison.
  - AIHW and RoGS: `row_dimensions_json` is `{name, value}` and column headings are
    text only; joined paths use " / " and " | ".
  - EEH: `row_group`, `row_label`, `estimate_type`, `statistic_basis`.
  - `observation.canonical_json`: `raw_*` fields are labels. `raw_lexeme` and
    `raw_semantic_scalar` are the value as text, not labels.
- **Accepted data points at the archived normalised copies.** Translate through
  `reference-only/reference-only.csv`.
- **Known database errors:** ISSUES.md I14. The database also keeps blank cells as
  observations with statuses (I5) and stores unrounded values for AIHW.
