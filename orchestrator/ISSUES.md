# Unresolved issues

Ordered by impact on the final tidy data. Each has evidence and a suggested next
step. Numbers are as of 2026-11-01, except I26 and I35 (2026-11-02).

## High

### I1. AIHW series without population or measure: resolved 2026-11-02
The rewritten AIHW recipes record their titles (I25), and `seed_aihw_rogs_specs.R` gives
every AIHW and RoGS title subject a population. Every group 1 record now has a
population. What's left is in I36.

### I2. Active sheets without a recipe: resolved 2026-11-02
Recipes now cover every sheet of the switched-on releases, including AIHW Child
protection 2021–22 to 2024–25 and RoGS Justice 2021–2026, which were switched on for
this (DECISIONS.md 33). The 92 EEH May 2021 sheets were not done: EEH is out of the
pipeline (DECISIONS.md 32).

### I3. Early recipes that fail the current validator: mostly resolved 2026-11-02
143 of the 181 early recipes that failed `validate_recipe` on naming were AIHW and RoGS.
They were moved aside and rewritten by the agents, with the rest of those publications
(DECISIONS.md 33). The other 38 (EEH, now switched off, and ABS pilot sheets) are
unchanged; their names are mapped by `normalise()`.

### I4. Nothing in the run loop checks that labels are correct
The validator checks structure only. The pipeline checks (README "Checks") test
invariants and completeness, not whether a label is the right one for a cell. Label correctness was checked after each batch
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

### I7. 779 `needs_review` recipes are a validator false alarm
557 contents and 222 notes sheets (522 of them from the victims publications) are flagged
table numbers or a concordance. The rule "non-data sheets must have no numeric cells"
is too strict.
**Next:** make it a warning for `contents`/`notes`, or allow small integers in a
contents list. Then re-run `submit_recipe` on those recipes (deterministic, no agent
cost).

### I8. Three genuine reviews: isolated numbers outside tables
Criminal Courts Northern Territory 2013–14 Tables 35 and 36 (new releases) have
isolated zeros outside the published tables (`B111`; `F16:F17`). The agents kept them
as annotations. The original case:

Criminal Courts 2023–24 cube 10, Table 53
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
`dictionary/proposed.csv` (regenerated 2026-11-02): 113 proposals, 65 of them from the
victims publications. Some are variants now covered by aliases. The 34 victims names
added overnight are marked "for owner review" in `dimensions.csv` (I34). Earlier ones:
33 declared names and 3 unmapped names (`Households`, `Supervision periods`, `order
outcome`). Likely merges:
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
reviewed. I35 merged most spellings; what's left:
- `state` has 14 labels: the three ACT prisoner labels ("ACT in ACT", "ACT in NSW", "ACT
  total"), "Total" and "Australia excl NT" beyond the nine canonical ones;
- `sex` has 26, including Boys/Girls, kept on purpose;
- `indigenous_status` has 18;
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

### I16. Git repository contents (fixed in the published copy; local history unchanged)
All commits (`35a2a6b`, `580c4f7`, `9b550de`) include:
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
  `" copy.json"` recipe. Since 2026-11-01 it no longer runs: it calls the old
  `one_enhead()` signature.
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
Resolved 2026-11-01: the script now writes `source_metadata.csv` itself, from
`sources/`. The old version is `sources/build_current_catalogue.R` (history). The owner
edits files in an editor that has overwritten agent edits before. Reload
`get_source_data.R` before saving.

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

### I31. New ABS justice releases: done, with leftovers to review
All 1,953 sheets of the 31 newly admitted releases have recipes: a pilot of 243 and then
the remaining 1,710, $41 in total (2026-11-01). Results:
- no error-level check failures; every new series has a population and a measure;
- 875,857 new values;
- `qa/review_new_releases.R` compares new values with other releases' values for the
  same series and period:

  | Publication | Equal | Within 5% |
  |---|---|---|
  | Prisoners | 99.8% | |
  | Recorded Crime | 85.3% | |
  | Federal Defendants | 82.1% | |
  | Courts | 67.8% | |

  Courts 2006–07 to 2011–12 agree at 82–96% (95–99% within 5%). Courts 2017–18 to
  2019–20 agree less (59–71%, 83–90% within 5%). There the labels match and the values
  are of similar size (ratio median 1.05), so these look like ABS revisions in later
  releases, mostly the 2020–21 release revising 2019–20. They're not confirmed:
  check ABS revision notes. `is_latest` takes the later release's value.

The spec work it needed is done: 98 subjects, 5 measure splits (court level inside the
measure), 37 reference dates, the `-`, `. .` and `—` symbols, legend-based `na`
meanings, combined court levels, cube codes for 2008–09 (verified, see
`measures/README.md`), and the "(excluding road traffic offences)" scope.

Left to review:
- **Courts 2011–12 (about 380 keys):** "Summary outcomes of all defendants" tables give
  slightly different proportions from "Defendants finalised" tables (28.2 vs 28.1), so
  "all defendants" may not equal defendants finalised (a judgement in the measure spec,
  I28).
- **Courts 2016–17 Table 1 (259 keys):** a publisher typo. Columns D and E are both
  headed "2011–12"; one should be 2010–11. Like `2022–22`, it needs a cell-level
  correction mechanism, which doesn't exist yet.
- **Unrecognised values (93):** revised figures with an `r` prefix (`r10,822`), and `_`.
  A `prefixes` rule in `value_spec.json` would read the number and flag it as revised.
- **Undated periods (9):** compound labels like "2006–07 NUMBER (no.)" (need a split),
  "2008–2009" (calendar or financial?), "2010-11r" (trailing revision marker).
- **ACT location labels:** "ACT in ACT", "ACT in NSW" (572 labels) are kept as published
  (I11).

### I33. Further speed-ups
At 9,040 sheets (2026-11-02), a rebuild that reruns every sheet takes about 23 minutes,
about 12 of them checks (`tar_make(names = integrated_files)` skips them). The per-sheet
stages are about three quarters of it, and the checks are the largest of those (0.34 s per
sheet).

Tried and not worth it:
- **Mapping over workbooks instead of sheets** (fewer, larger branches): 5% faster on
  1,000 sheets, or 16% after the 2026-11-02 code changes. A recipe edit would also rerun
  its whole workbook. The earlier estimate of a 10-minute full rebuild was too optimistic.
- the metadata write interval, the store's location, byte-compiling the stage functions,
  and forking `assemble()`, which ran out of memory.

Not tried:
- **Rerunning only the sheets a spec edit affects**, by giving each sheet's branch only
  the spec entries its labels use. A typical label edit touches about 10 sheets (median;
  90th percentile 88), so most spec edits would take minutes. It needs a slicing step per
  spec and can leave stale output if that step is wrong. It doesn't help `clean` rules or
  common labels such as `Number` (6,213 sheets), and still needs an occasional full
  rebuild.
- **8 workers instead of 6:** about 10% faster on 1,000 sheets, but it leaves little CPU
  for anything else and wasn't tested for heat over a full rebuild.
- **Cheaper checks.**
- Assembling per sheet in its own branch would make `assemble()` incremental, at the cost
  of 9,040 more branches.

### I34. Victims publications: leftovers and overnight judgement calls
All 3,831 sheets of the two ABS victims publications (39 releases) have recipes and are
in the integrated dataset: 1,361,638 values (2026-11-02).
- Every series has a population and a measure, except 9 Recorded Crime – Victims series
  from sheets without a title.
- Republished values match the latest release: Crime Victimisation 98.2%; Recorded
  Crime – Victims 88.8% (96.0% within 5%, median ratio 1.00 in every release, so
  revisions rather than mislabelling).

Judgement calls made overnight, for the owner to confirm (each is a rule in
`qa/seeds/seed_victims_specs.R` or a spec entry):
- **Survey populations.** Victims of personal crimes are persons aged 15 and over (18
  and over for sexual assault); victims of household crimes are households; "persons"
  without an age means 15 and over.
- **The crime from the title** becomes `crime_type` (CV) or `victim_offence` (RCV).
  Family and domestic violence becomes `scope`.
- **`estimate_type`.** Agents often put a column heading or the whole title in it.
  RSE-like labels became "Relative standard error", everything else "Estimate". Most
  estimates have no `estimate_type` at all, so the same estimate can sit in two series
  (empty vs "Estimate"), like I27's implicit totals.
- **Upper-case labels** in victims dimensions were mapped to sentence case. The
  mapping is global, so labels in other publications merged too; labels that split
  rules are keyed on were excluded.
- **Quality flags** (`value_flag`) from asterisks and markers (decision 29).
- **Dictionary:** 34 names added, marked for owner review; variant names mapped by
  normalisation.

Left to review:
- **Crime Victimisation, about 1,350 keys inside single sheets:** two cells with the same
  labels, e.g. Table 30a B86 vs C86 (2017–18). A heading is missing from the recipe;
  needs agent reruns of those sheets.
- **Crime Victimisation RSE tables "b" and "d" (e.g. 6b vs 6d, 2010–11):** they differ
  only by table letter. Probably RSE of estimates vs RSE of proportions; check the
  contents sheets, then add `title_flags`.
- **Recorded Crime – Victims, about 1,350 keys:** mostly tables that differ by a
  breakdown named only in the title.
- **Population rows from the tables** ("All persons", "Victims experiencing one or
  multiple incidents") stay as published: about 1.7% of victims records.
- **`dictionary/proposed.csv`:** 65 victims proposals, including variants now
  covered by aliases.

### I35. Label consistency: done 2026-11-02, with leftovers
An audit of the integrated tables found labels split one thing into many, and some
values mislabelled. `qa/seeds/seed_label_consistency.R` (rules in `consistency_rules.R`,
starting from `consistency_baseline/`) and small changes to `identify()` and `reconcile()`
fixed most of it. No cell changed: all 3,989,690 keep the same text, value, status, flag
and release.

| | Before | After |
|---|---|---|
| Series | 721,701 | 661,477 |
| Measures | 1,408 | 1,101 |
| `measure` labels | 403 | 281 |
| `state` / `sex` / `court_level` labels | 41 / 44 / 30 | 14 / 26 / 15 |
| `age_group` labels | 285 | 153 |
| Series with no `unit` | 535,545 | 48,629 |
| Period labels | 228 | 158 |
| Rows with no `reference_date` | 2,068 | 236 |
| Series and dates with two latest values | 14,368 | 687 |
| `Number` series with a statistic in a dimension | 562 | 0 |
| Label spelling groups, by the new check | 369 | 25 |
| Values that can't be told apart | 9,511 | 9,988 |

The rise in the last row is the cost of merging: 452 keys where a spelling or a mislabel
was all that separated two tables. Most are the same quantity published slightly
differently in two tables (`52` vs `50`), the rest different denominators (I26). They
were always there; `is_latest` now picks one of each pair instead of keeping both.

Judgement calls, for the owner to confirm (each is an entry in `consistency_rules.R`):
- **Survey headings.** `Persons`, `Households` and `Estimates` beside `PROPORTION` are
  counts, so `Number`; in RSE tables the `%` is the RSE's own unit. `Victims`, `Non-victims`
  and `All persons` move to `victimisation_status`.
- **A plain year replaces `30 June YYYY`** in Prisoners and child protection, so `period`
  isn't always the publisher's wording. `Dec YYYY` replaces `December YYYY`.
- **Family and domestic violence is `scope`,** not `population`, in every publication
  where the subject says so.
- **Columns merged** (from I10): `duration` into `case_duration`, `fine_value_band` into
  `fine_amount`, `weekly_cash_earnings_band` into `weekly_total_cash_earnings_band`, the
  defendant and offender rate bases into `rate_standardisation`. `Summary characteristics`
  into `federal_defendant_summary_item`, `Relationship` into `carer_relationship`,
  `Supervision` into `supervision_history`.
- **`period_type`** is a series column, so pooled and multi-year periods are separate
  series. `Range of N years` counts the years from first to last.

Left to do:
- **`order outcome` is still a column** (126 child protection series). The rename moved
  its `split` entries to `order_outcome`, but their inner field keeps the old name. Rename
  the field in the seed's rename loop; it takes a full rebuild, about 23 min (11 without
  the checks). The 1 h 47 min rebuild on 2026-11-02 was slowed by a leftover staging
  process, not the pipeline.
- **25 spelling groups** (1,311 series), which `labels_have_one_spelling` lists. Most are
  upper-case `measure` labels also used in another column (`CRUDE RATE`, `TOTAL`), and
  the Youth Justice labels in `unsafe`, which need titles first (I25).
- **Denominators are named only for police proceedings tables.** About 1,200 other
  cross-release proportion pairs differ by over 1.5 times (Recorded Crime – Victims 912,
  Prisoners 148, Crime Victimisation 121), some probably the same problem. Check Total
  rows as for police proceedings, then add `denominators`.
- **`Experienced X in the last 12 months`** and similar Crime Victimisation headings are
  still in `measure`; they belong in `victimisation_status` plus `crime_type`.
- **234 series have `Number` with `%` and aren't RSEs:** survey percentages under a
  heading now treated as a count.
- **Federal Defendants rows with no label** (e.g. "Federal offences" in the Table 1 state
  tables) need recipe fixes: 74 fractional `Number` rows remain.
- **Total labels** still vary by table (`Defendants`, `All persons`, `Total finalised`).
  That's `classify()` (I6, I27).

### I25. Early AIHW recipes without a title: resolved 2026-11-02
The early AIHW recipes were rewritten (I3). Youth Justice sheets that stack several
titled tables ("Table S126a", "S126b") record a title per table, and `identify()` reads
each table's title when the sheet has none.

### I26. Some values still can't be told apart
`tar_read(integration_gaps)$identity_conflicts` counts keys with the same series, period
and release but different published text. "Two different numbers" means the gap is
real. "Number vs symbol" is mostly harmless (a mean-age row crossing a rate panel).

| Publication | Two different numbers | Number vs symbol |
|---|---|---|
| Crime Victimisation | 2,246 | 1 |
| Recorded Crime – Victims | 1,397 | 0 |
| Courts | 1,008 | 0 |
| Recorded Crime – Offenders | 571 | 7,375 |
| Prisoners | 315 | 76 |
| Youth Justice | 129 | 75 |
| Federal Defendants | 108 | 0 |
| child protection | 71 | 254 |
| RoGS | 0 | 0 |

AIHW and RoGS figures are after their recipes were rewritten on 2026-11-02 (I36); before,
child protection had 2,621, Youth Justice 1,709 and RoGS 13.

The label consistency work (I35) added 452 keys.

The victims seed (2026-11-02) merged label spellings in all publications ("SELECTED
OFFENDERS" vs "Selected offenders"). This raised Recorded Crime – Offenders from 185 to
455 and Prisoners from 160 to 204. The new keys are the same quantity published in two
tables with slightly different numbers (22.1 vs 22.2), which previously looked distinct
only because of the spelling.

AIHW and RoGS are in I36. For the rest, `Rscript orchestrator/qa/integration_conflicts.R
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
`observations.csv` is 847 MB (3,989,690 rows) and `series.csv` 249 MB (721,701 rows ×
195 columns, mostly empty): 1.1 GB in total after the victims publications.
**Next:** if size matters, gzip them (readr reads `.csv.gz` directly) or move `series`
to a long format.

### I36. AIHW and RoGS ("group 1"): judgement calls and leftovers
Added 2026-11-02 (DECISIONS.md 33):
- AIHW Child protection 2020–21 to 2024–25: 228,007 values;
- AIHW Youth Justice 2024–25: 60,193 values;
- RoGS Justice 2020–2026: 537,398 values.

Every record has a population, and every RoGS record a measure, unit and reference date.
Publications outside group 1 are unchanged, value for value.

Judgement calls, each a rule in `qa/seeds/seed_aihw_rogs_specs.R`, for the owner to
confirm:
- **AIHW populations** are the title's subject up to "by …". Qualifiers stay, so "on an
  average day" and "during the year" are different populations.
- **RoGS populations and measures** are hand-written per indicator. Survey indicators
  count persons aged 15 and over. "(before 2023-24)" survey tables get scope "Survey
  before 2023–24", because the question changed.
- **Plain years:** RoGS plain years are calendar years (31 December), from the police
  tables sourced from ABS Recorded Crime – Victims. Child protection plain years stay
  30 June. Its "as at 31 December" population tables get scope "At 31 December", but
  their `reference_date` is still 30 June of that year.
- **Youth Justice rates** are per 10,000 young people (from the table notes). Untitled
  Youth Justice measures default to Number.
- **Merged names:** where two agents named one concept differently, one name was kept
  (e.g. `custody_type` → `prison_security`, `rate_basis` → `rate_standardisation`). The
  59 new dictionary names are marked for owner review.
- **State labels:** "Total" stays (68 earlier series use it too). RoGS "Aust cts"
  (Australian, i.e. federal, courts) stays.

Leftovers:
- **Values that can't be told apart** (`integration_conflicts.R`): 71 child protection and
  129 Youth Justice keys with two different numbers, mainly:
  - child protection P1 vs P2: identical titles, ABS population from different
    sources;
  - Youth Justice S147a vs S147b: the second adjusts for the changed minimum age of
    criminal responsibility, which only a footnote says;
  - about 70 child protection keys where two tables' totals disagree (T2.2 vs Table 2.5,
    Table 4.3 vs 4.4).
- **Gaps:**
  - about 1,100 child protection records have no measure;
  - about 2,000 child protection and 1,300 Youth Justice records have no unit (measures
    such as "Number of children");
  - Youth Justice months without a year (312 records) and the "Dec 208" typo (90)
    have no `reference_date`.
- **Unrecognised values:** `<0.1` and `>99.9` (6 child protection values).
- **Combined dimensions** could be split in harmonisation:
  `reunification_status_age_group`, `order_type_reunification_status`,
  `care_arrangement_and_indigenous_status`.
- **Long RoGS measure labels** ("Proportion of recorded victims of sexual assault, by
  age at incident"). The label consistency seed (I35) predates group 1 and hasn't been
  applied to its labels.

`run_recipe` now fails when two value cells have the same labels but different values
(`layouts.md`, "Cells that differ only by position"). In the pilot it caught RoGS
confidence-interval columns and an AIHW "Category" column put in `table_subtitle`.

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
| R15 | Found by the new checks: 13 chains in the normalisation spec (e.g. "Higher(a)" → "Higher" → "Higher Courts") left middle labels on 80 sheets | Chains resolved in the JSON; `check_data_normalised()` catches new ones |
| R17 | Automated XLS/XLSM conversion with Excel: the first test stalled on an Excel dialog. The script also chose "the active workbook" (which could have been the owner's) | Conversion inside Excel's container, acting on its own workbook by name. Works once Excel has no dialog open; tested on 5 XLS files (incl. Excel 95 and ZIP members) with values identical to the originals |
| R18 | Any change to `source_metadata.csv` that touched every row (e.g. the first prepared national source adds 26 columns) would have rebuilt every sheet's branches | `recipe_sheets` keeps only the fields processing reads (plus `xlsx_sha256`) |
| R19 | Value symbols assumed one meaning per publication, but Recorded Crime 2019–20 to 2024–25 (and two Prisoners 2025 workbooks) say "na = not applicable" | Workbook-level entries in `value_spec.json` from each workbook's own legend (`qa/seeds/seed_value_legends.R`, 33 workbooks); `type_values()` looks up workbook, then publication, then default |
| R20 | "Magistrates' & Children's Courts" titles were labelled Children's Courts (one title-rule match) | Combined level as its own alternative in the court-level rule |
| R21 | `check_data()` counted only non-blank records against validator counts that now include blanks | Accepts either count |
| R22 | Older releases' untidy labels (`'  SA   '`, `'NSW(a)  '`, `'2018–19(b) '`) | A `clean` section in the normalisation spec (whitespace, trailing footnote markers, leading revision `r`), also applied to the value maps' keys; `normalise()` is 32 lines. Existing data: 48 labels in 2 sheets changed; values untouched |
| R23 | 2008–09 Courts cubes 2–4 name their court level only in the cube code (4,052 indistinguishable keys) | Cube rules in the measure spec, verified by value matching (99%, 96%, 96%) |
| R24 | A recipe gave one heading ("Aboriginal and Torres Strait Islander (%)") as both Indigenous status and measure, so the measure split contradicted it and stopped the build | `split` entry for that Indigenous status label. Listed all contradictions first by running `harmonise()` over every branch |
| R25 | Excel's macro prompt blocked automated conversion (it ignores the automation settings) | Macro workbooks detected first; converted with Excel set to disable macros without notification (`EXCEL_MACROS_DISABLED=1`); Excel's settings recorded and restored |
| R26 | Old ABS `download_url` links answering "Attachment Not Found" | `get_source_data.R` also tries `source_url`, keeping the first whose bytes match the pin |
| R27 | High-RSE asterisks added by number formats were dropped from published values (about 10,000 survey estimates presented as reliable) | `published_value()` keeps quoted asterisks; `markers` in the value spec set `value_flag` |
| R28 | The measure spec's subject pattern was case-insensitive in its table-letter suffix, so "Table 6PERSONS" lost its "P" | `(?-i:[a-z])?` in `subject_pattern`. 16 sheets changed; the Federal Defendants "ummary…" workaround key is no longer needed |
| R29 | Recorded Crime – Victims values couldn't be told apart (12,230 keys): a "Queeensland" title, "–2007 revised" periods, age basis only in titles, FDV tables | Title rules, `age_basis` flags, FDV as scope: down to 1,356 |
| R30 | A tool-call timeout killed a background rebuild (process-group kill) | Pitfall in README; long jobs launched detached in their own call |
| R16 | Found while checking R15: "Total prisoners" mapped to "Prisoners" even in Federal Prisoners tables, and the subject "FEDERAL OFFENCES" mapped to "Federal prisoners and parolees" for tables that are one or the other | "Total prisoners" → "Total" (`replace_labels` gives each table's population); title rules for "offences for federal prisoners/parolees". Prisoners conflicts went from 177 to 144 |
