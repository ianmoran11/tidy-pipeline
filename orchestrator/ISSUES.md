# Unresolved issues

Ordered by impact on the final tidy data. Each has evidence and a suggested next
step. Numbers are as of 2026-11-01.

## High

### I1. AIHW series have no population or measure (ABS and RoGS are complete)
`identify()` (2026-11-01) gives every ABS and RoGS series a `population` and a
`measure`. AIHW is the exception:
- child protection: 4,541 of 8,588 series have no population, 914 no measure;
- Youth Justice: 3,660 of 4,330 have no population, 3,516 no measure.

The cause is I25: their early recipes have no title.
**Next:** fix I25, then add AIHW subjects to `measures/measure_spec.json`.

### I2. 1,254 active sheets have no recipe
AIHW child protection 440, RoGS 608, AIHW Youth Justice 114, EEH 92 (deferred by the
owner). Their publications have only pilot-era recipes as templates, which use old
names (I3). RoGS has deep row outlines that map poorly onto single dimensions (see
`agents/skills/.../references/naming.md`, "Report on Government Services outlines").
**Next:** run a small pilot per publication, review it against the database
(`qa/`), and update `layouts.md` before a full batch.

### I3. 181 early recipes fail the current validator (naming only)
The 208 recipes outside the three ABS batches (pilot and tests, 2026-10-31) were
written before `dictionary/dimensions.csv` existed. Checked 2026-11-01: 181 fail
`validate_recipe` today, every error about names, none structural. They include 74 of
79 child protection recipes, 43 of 47 Youth Justice and 26 of 28 RoGS. These are the
templates agents will find for the remaining 1,254 sheets (I2).

The problems:
- publisher wording as names (`Year`, `Principal offence`, `Age group (years)`),
  handled by `normalise()`;
- names to avoid (`category`, `characteristic`, `section`, `group`, `offence`), partly
  handled by `harmonise()` unstacking;
- numbered or wrong sheet meta names (`stub_heading_1` …, `table_identifier`,
  `notes_and_worksheet_annotations`).

Their `validated` status comes from an older, weaker validator.
**Next:** migrate mechanically (rename to dictionary names using the validator's
own suggestions, then `submit_recipe` again; no agent cost). Do this before the
AIHW/RoGS batches. Alternatively, rerun the agents on those workbooks (move the old
recipes aside first; the queue skips validated sheets).

### I4. Nothing in the run loop checks that labels are correct
The validator checks structure only. Label correctness was checked after each batch
with the scripts in `qa/` against the reference database. Those checks found two real
errors (I-resolved R4), so they matter.
**Next:** make the comparison a post-batch step (e.g. a `targets` target or a
`qa/run_checks.R`) that flags sheets whose disagreements are not of the known benign
kinds. Do not use it as a validator gate: the database has its own errors (I14).

### I5. Blank rows and columns are still missing (blanks inside tables are done)
The owner decided blank cells should be records with a status (DECISIONS.md 19).
`blank_value_cells()` now adds blank cells where a value row and a value column of the
same table cross: 23,295 records, 17,056 of them in EEH's sparse tables.

`qa/blank_cells_vs_reference.R` (250 sampled historical ABS sheets): every blank it
found is a blank the database also records (precision 100%). It finds 42% of the
database's blanks: 15% for Prisoners, 34% Federal Defendants, 46% Courts and 52%
Recorded Crime.

The rest are rows or columns that are blank throughout (e.g. Prisoners 2009 cube 2
Table_10 row 103, ACT prisoners held in NSW in 2009). The validator rejected blank
value cells, so agents left those rows out of the table, labels included. The pipeline
has no label to give them.
**Next:** let recipes include blank cells. Allow blanks in `values_range` when the row
or column has a label, and change the validator and skill. Then rerun the agents, or
write a tool that extends existing tables to label-only rows next to them. The logic
is in `R/blank_value_cells.R`; measure progress with `qa/blank_cells_vs_reference.R`.

### I6. Totals, subtotals and hierarchy are not structured
Totals sit next to their components, and parent rows (e.g. ANZSOC divisions above
subdivisions) are in the same dimension as their children. This is described only in
free-text `agent_notes`. In older Courts sheets about 15% of cells lack a parent label
("Adjudicated outcomes", division headings). Summing a dimension double-counts.
**Next:** stage 7, `classify()`, agreed in DECISIONS.md 16. Add an `is_total` flag from
label patterns and a parent from codes ("01", "011") or indentation (tidyxl gives indent
levels). Do this together with I27 (implicit totals).

## Medium

### I7. 222 `needs_review` recipes are a validator false alarm
221 contents and 1 notes sheets are flagged because they contain numbers, which are
table numbers or a concordance. The rule "non-data sheets must have no numeric cells"
is too strict.
**Next:** make it a warning for `contents`/`notes`, or allow small integers in a
contents list. Then re-run `submit_recipe` on those recipes (deterministic, no agent
cost).

### I8. One genuine review: Criminal Courts 2023–24 cube 10, Table 53
Unlabelled numbers below the copyright line (`B66:O67`, `B122:O122`, `B174:O175`)
repeat Table 52's age statistics. The agent kept them as annotations and asked for
review.
**Next:** a person decides whether to drop or label them.

### I9. Two values sharing the same labels is not checked
Prisoners 2011 cube 2, Table_6: the Females block labels two rows "Median age" (the
first should be "Mean age"; Males and Persons have Mean then Median). Recipe and
database both keep the published labels, so 18 cells share their labels with another
cell and can't be told apart.
**Next:** add a clash check to `run_recipe` (duplicate label sets in a sheet →
failure), and add a `split` or normalisation entry for this sheet's row 38.

### I10. Dictionary proposals are waiting for review
`dictionary/proposed.csv`: 33 declared names and 3 unmapped names (`Households`,
`Supervision periods`, `order outcome`). Likely merges:
- `rate_standardisation`, `defendant_rate_basis`, `defendant_rate_type`,
  `offender_rate_basis` (crude vs age-standardised);
- `weekly_total_cash_earnings_band` and `weekly_cash_earnings_band`;
- `fine_amount` and `fine_value_band`;
- `federal_offence_group` and `principal_federal_offence_group`;
- `prior_adult_imprisonment` and `prior_imprisonment_status`;
- `prison_type`, `custody_facility_type` and possibly `prison_location`;
- `measure_transformation` and `change_measure`;
- `sentence_length_group` (parent of `sentence_length`).

**Next:** the owner decides. Add accepted names to `dimensions.csv`, and merges to
`aliases` and to `normalisation_spec.json` `dimension_names`.

### I11. The normalisation spec is a first version
It was generated by rules (`qa/seeds/seed_normalisation_spec.R`) and only partly
reviewed:
- `state` still has 37 labels: ACT prisoner variants such as "ACT in NSW" and
  "ACT IN NSW", case variants, and "Australia excl NT";
- `sex` has 21, including Boys/Girls, kept on purpose;
- `indigenous_status` has 24;
- `"Total"` is not mapped to Australia, on purpose;
- other dimensions only lost footnote markers and extra spaces;
- publisher typos: "NEWS SOUTH WALES", "Dedendants finalised" and "Defendants proven
  guitly" are fixed, others may remain;
- added 2026-11-01: `population` spellings (Federal Defendants, Prisoners, FDV
  offenders) and `sentence_basis` (five spellings into two).

**Next:** review the distinct labels per dimension (`qa/harmonise_labels.R` lists
them) and extend the JSON.

### I12. Harmonisation leftovers
- **58 compound labels remain** (`qa/after_scan.R`). Most are correct as they are:
  rate ratios, `rate_of_pay: "Adult rate"`, prison names. To decide:
  - `age_group: "Mean age (youth)"` (256 records);
  - `indigenous_status: "Mean (years)"` / `"Median (years)"` / `"Rate ratio for age groups"`;
  - the old Federal Defendants `Summary characteristics` header;
  - `abuse_type: "Average co-occurrence"`;
  - `population: "(Sentenced prisoners in NSW prisons)"`.
- **2,752 records keep `characteristic`/`category`,** because the characteristic (e.g.
  "Federal defendants") is not in `unstack.names`.
- **Two periods have no `reference_date`:** `Dec 208` (Youth Justice, 90 records) and
  `2022–22` (Courts 2021–22 cube 11 Table 51, 146 records; the archived normalised
  copy corrects it to 2021–22). Both are publisher typos.

**Next:** add `split`/`unstack` entries, and dates for the typos if the owner agrees.

### I13. Title rules are unverified at scale, and state completeness is not reported
`from_title` filled `state` for 505,204 records and `period` for 638,292.
- **Fixed 2026-11-01:** subtitles outvoting a different title period (R11; it affected
  2 sheets) and singular court-level names ("Magistrates' Court").
- **Remaining risk:** national tables not phrased "– Australia" get no state.
`harmonisation_report()` reports missing period, reference date and measure, but not
state.
**Next:** sample derived values per publication against the database (accepted
observations carry `raw_jurisdiction` and `raw_observation_period`), and add state to
the gap report for publications reported by state.

### I14. Errors found in the reference database (owner's product) are unreported
Confirmed against the sheets:
- AIHW child protection 2020–21: about 6,500 cells where the first block's label
  ("Indigenous children", "Home-based") is applied to every block;
- Youth Justice S29: a data row treated as column headings, and one block's measure
  applied to all blocks;
- child protection S5.9: the second table (S5.9b) is missing;
- child protection T2: the year heading row stored as data;
- stray unlabelled cells stored as observations (Youth Justice S25, S7, S15, S4, S18);
- placeholder labels such as "column b".

**Next:** tell the owner. These matter for any use of the database, and the database
should not be treated as ground truth in QA.

### I15. Database accepted data points at archived copies
Accepted observations (`asset.source_digest`) mostly reference the normalised copies
now in `reference-only/`, not the active originals. The cell addresses are the same.
**Next:** when joining recipes to the database, map through
`active_sha256` in `source_metadata.csv` (from `reference-only/reference-only.csv`),
as `qa/compare_accepted.R` does.

## Low / housekeeping

### I16. Git repository contents
The single commit includes:
- `tidy-data-asset-status.sqlite3` (9.4 GB), its `.gz` (306 MB) and
  `source-spreadsheets-xlsx.zip` (71 MB): `.git` is 726 MB, and hosts such as GitHub
  reject files over 100 MB;
- an Excel lock file
  (`source-spreadsheets-xlsx/~$819a9038…cube-5-source.xlsx`);
- `.DS_Store`;
- `_targets/meta/meta`.

The top-level `.gitignore` (added 2026-11-01) lists only `integrated/`.
**Next (with the owner's agreement; rewriting history is hard to undo):** untrack the
large files or use Git LFS, and add a `.gitignore` for `*.sqlite3*`, `~$*`,
`.DS_Store`, `_targets/`.

### I17. Stale files
- `run_recipe.R` (project root): early exploratory code; one part reads a
  `" copy.json"` recipe.
- `source-spreadsheets-xlsx/R/`: an empty folder.
- The Excel lock file, if Excel is no longer open.

### I18. Agents see stored, not published, numbers
`sheet_grid` (`agents/tools/recipe_tools.R`, `read_sheet()`) shows
`as.character(numeric)`, e.g. `2.37887238760836` where the sheet shows `2.4`. This
doesn't affect recipes, but it makes grids longer.
**Next:** use `published_value()` in `read_sheet()`.

### I19. Some recipes list cells one by one
`values_range` sometimes lists single cells (up to 1,620 parts, Youth Justice S33).
The recipes are correct but hard to review.
**Next:** have `submit_recipe` compress runs into ranges.

### I20. Smaller extraction limits
- `process_recipe()` output field is spelled `sheet_metata`.
- Error cells (`#N/A`) are not in the `coalesce()` and become `NA`. There are none in
  the current corpus.
- `published_value()` keeps the stored number for percentage, scientific, fraction
  and `General` formats. None are used by value cells today.
- `TIDYXL_BUILTIN_FIXES` assumes `"#;##0"`-style strings always come from Excel's
  built-ins. A custom format with that exact text would be misread.

### I21. `get_source_data.R` workflow
It does not write `source_metadata.csv`; the CSV is written by hand from
`source_data_df_04`. Edits to it were twice lost when the owner's editor saved an
older copy.

### I22. No reviewer agent driver
`agents/prompts/reviewer.md` exists, but nothing runs it.

### I23. Costs are estimates
`queue.R costs` uses Pi's API-price estimates. Pi does not price the priority tier when
an extension sets it (`queue.R` doubles fast runs). Usage against the ChatGPT plan's
allowance is not measured.

### I24. The recipe format cannot express values that are only in a title
Mitigated downstream by `harmonise()` `from_title`, which covers state, court level,
period, estimate type and some Indigenous status. Agents still cannot record such
values themselves.

### I25. Early AIHW recipes have no title, so `identify()` has nothing to read
110 early AIHW sheets have no `table_title` in their recipe: 76 child protection and
34 Youth Justice. The pilot agents never recorded the title cell. This causes the AIHW
gaps in I1 and the AIHW identity conflicts in I26. Renaming fields can't fix it.
**Next:** rerun the agents on the early recipes that fail today's validator (I3). That's
181 sheets, about $4 at API prices. Move the old recipes aside first; the queue skips
validated sheets. This fixes I3 and I25 together.

### I26. Some values still can't be told apart
`tar_read(integration_gaps)$identity_conflicts` counts keys with the same series, period
and release but different published text. "Two different numbers" means the gap is
real. "Number vs symbol" is mostly harmless (a mean-age row crossing a rate panel).

| Publication | Two different numbers | Number vs symbol |
|---|---|---|
| child protection | 2,621 | 3 |
| Youth Justice | 1,709 | 75 |
| Prisoners | 177 | 74 |
| Courts | 87 | 0 |
| Recorded Crime | 35 | 6,556 |
| RoGS | 13 | 5 |
| Federal Defendants, EEH | 0 | 0 |

AIHW is I25. For the rest, `Rscript orchestrator/qa/integration_conflicts.R
<publication_id>` shows the tables involved. For example, Courts "Summary
characteristics of defendants" vs "of all defendants" in the same cube.
`reconcile()` still flags exactly one value as latest, preferring numbers over symbols.

### I27. Implicit totals: an empty dimension means "total"
A table without a sex breakdown has no `sex` field, so the same total appears as
`sex = "Persons"` (from by-sex tables) and as an empty `sex` (from other tables). They
are different series.

Example: the Prisoners age-standardised rate has `sex = "Persons"` up to 2021 and no
`sex` from 2022. Filtering `sex == "Persons"` silently loses 2022 onwards.
`integration/README.md` tells analysts to filter `is.na(sex) | sex == "Persons"`.
**Next:** the `classify()` stage (DECISIONS.md 16). It should mark totals (`is_total`)
and fill implicit totals with the dimension's total label where the publication has
that dimension.

### I28. Judgement calls in the specs, for the owner to confirm
Each is a JSON entry that's easy to change:
- ABS "proven guilty" = "with a guilty outcome" (the terminology changed);
- Criminal Courts "summary characteristics of all defendants" = defendants finalised;
- combined "finalised and with a guilty outcome" tables count defendants finalised;
- population "Total" = the population named in the title;
- Prisoners "EXPECTED SENTENCE" (older releases) = "Expected time to serve";
- AIHW "-" = nil or rounded to zero (one cell);
- blank cells get status `blank`, not a guessed meaning;
- the old Courts cube → court level mapping. This one is checked against the data
  (`measures/README.md`), not stated anywhere by the ABS.

### I29. Integrated CSVs are large
`observations.csv` is 369 MB (1,752,195 rows). `series.csv` is 102 MB, with 382,398
rows and 114 columns, mostly empty. Both read in R in about 6 seconds.
**Next:** if size matters, gzip them (readr reads `.csv.gz` directly) or move `series`
to a long format.

## Resolved (for reference; do not redo)

| | Problem | Fix |
|---|---|---|
| R1 | Wrong sheet read (tidyxl index ≠ tab order) | Read by name; validator checks the sheet name |
| R2 | AIHW values unrounded | `R/published_value.R` |
| R3 | Sheet names with trailing spaces lost | `trim_ws = FALSE` in all readers; two recipes re-run |
| R4 | Two Courts 2024–25 recipes took `court_level` from value cells | Validator check added; both re-run |
| R5 | EEH estimates and standard errors had identical labels | `harmonise()` `estimate_type` from titles |
| R6 | Periods/states only in titles | `harmonise()` `from_title` and fallback |
| R7 | 76 redundant workbook copies | Archived to `reference-only/`; validator and queue skip them |
| R8 | Excel lock file broke `get_source_data.R` | Skipped |
| R9 | `harmonise()` partial `$` matching put lists in fields | `[[ ]]` lookups |
| R10 | Contradicting splits (`(%)` rows vs column units) | Normalised units; `_replace` for unit; split order |
| R11 | The subtitle's release period outvoted a different period in the title, so the release period was used: 2 Recorded Crime 2010–11 sheets (1,248 cells) were stamped 2010–11 instead of 2009–10 | `harmonise()` reads the title first, then the subtitle |
| R12 | 2009–10 and 2010–11 Criminal Courts cubes name their court level only in the cube code | `title_flags` in the measure spec, mapping checked against the data |
| R13 | 167,000 values in one release couldn't be told apart (title-only population); 761,000 records had no measure | `identify()`. ABS identity conflicts are down to a few hundred (I26) |
| R14 | Publisher symbols in 12 spellings | `type_values()` with per-publisher meanings; 0 unrecognised |
