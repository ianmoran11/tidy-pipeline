# State at handover (2026-11-03, after adding the group 2 national publications)

## Corpus

| | Count |
|---|---|
| Workbooks in `source-spreadsheets-xlsx/` (active) | 1,234 (545 from the original package, 689 prepared from the national catalogue) |
| Archived reference-only copies (`reference-only/`) | 76 (608 sheets) |
| Sheets in `source_metadata.csv` | 11,612 |
| Active sheets | 11,004, of which 10,675 are in switched-on releases |

## Recipes

10,912 recipe files: 10,675 for the switched-on releases (9,137 data, 1,022 contents, 516
notes), plus 237 for Employee Earnings and Hours, which is switched off (DECISIONS.md
32):
- 3,256 for the original package's active sheets, less the 146 early AIHW and RoGS
  recipes rewritten on 2026-11-02;
- 1,953 for the new ABS justice releases (2026-11-01);
- 3,831 for the two ABS victims publications (2026-11-01/02);
- 1,324 for AIHW Child protection, AIHW Youth Justice and RoGS Justice (2026-11-02:
  1,162 new sheets plus the 146 rewritten and 16 pilot sheets redone);
- 710 for the 13 group 2 national publications (2026-11-03: 652 data, 35 contents, 23
  notes).

| Status | Count | Note |
|---|---|---|
| validated | 10,099 | |
| needs_review | 813 | Mostly the validator's false alarm on numbers in contents and notes sheets (ISSUES.md I7); 3 data have isolated numbers outside their tables (I8); Personal Fraud Table 9b (I37) |

Admitted sheets (switched-on releases) by publication, all with recipes:

| Publication | Admitted sheets |
|---|---|
| crime-victimisation-australia | 2,501 |
| criminal-courts-australia | 2,101 |
| recorded-crime-victims | 1,330 |
| prisoners-australia | 1,257 |
| recorded-crime-offenders | 1,058 |
| pc-report-on-government-services-justice | 636 |
| aihw-child-protection-australia | 519 |
| federal-defendants-australia | 402 |
| aihw-health-people-australias-prisons | 270 |
| aihw-youth-justice-australia | 161 |
| partner-violence | 66 |
| aihw-youth-detention-population-australia | 57 |
| personal-safety-australia | 52 |
| pc-rogs-child-protection | 45 |
| personal-fraud | 37 |
| corrective-services-australia | 34 |
| stalking | 33 |
| pc-rogs-youth-justice | 29 |
| sexual-violence | 25 |
| aihw-youth-justice-child-protection | 22 |
| aihw-young-people-returning-youth-justice | 21 |
| childhood-abuse | 19 |
| **Total** | **10,675** |

`agents/queue.csv` (switched-on releases only): 1,189 workbooks, all done.

The 38 remaining pre-dictionary recipes (EEH and ABS pilot sheets) fail today's
validator on naming only; `normalise()` maps their names (ISSUES.md I3).

## Agent runs

| Batch | List | Sheets | Wall clock | Est. cost (API prices) |
|---|---|---|---|---|
| Pilot + tests | — | ~210 | — | ~$3 |
| ABS 2025 → 2021-22 | `agents/batch-abs-1000.txt` | 1,005 | 31 min | $20.67 |
| ABS 2021-22 → 2014-15 (no EEH) | `agents/batch-abs-1000-b.txt` | 1,000 | 31 min | $20.76 |
| ABS 2014-15 → 2006 (no EEH) | `agents/batch-abs-rest.txt` | 1,043 | 42 min | $23.06 |
| New ABS justice releases, pilot (2001 → 2019-20, all 4 publications) | `agents/batch-abs-new-pilot.txt` | 243 | 12 min | $5.99 |
| New ABS justice releases, the rest | `agents/batch-abs-new-rest.txt` | 1,710 | 48 min | $35.05 |
| Victims publications, pilot | `agents/batch-victims-pilot.txt` | 239 | 10 min | $4.15 |
| Victims publications, the rest | `agents/batch-victims-rest.txt` | 3,592 | 2 h 11 min | $61.28 |
| AIHW and RoGS, pilot | `agents/batch-aihw-rogs-pilot.txt` | 101 | about 15 min | $1.21 |
| AIHW and RoGS, the rest | `agents/batch-aihw-rogs-rest.txt` | 1,223 | about 1 h | $15.15 |
| National (group 2), pilot | `agents/batch-national-pilot.txt` | 157 | 6 min | $1.89 |
| National (group 2), the rest | `agents/batch-national-rest.txt` | 553 | 17 min | $5.90 |
| **All runs** | `agents/runs.csv` | | | **$197.99** (1,233 runs) |

Costs are Pi's estimates at API prices; on the owner's ChatGPT plan they draw on
subscription allowance instead.

## Pipeline outputs

| Target | Value |
|---|---|
| `data` | 10,675 sheets (every admitted sheet with a recipe) |
| `data_normalised`, `data_harmonised`, `data_identified` | same records; every record has `period`; 548 lack `reference_date` (the publisher typos `2022–22` and `Dec 208`, and Youth Justice months without a year; ISSUES.md I12, I36) |
| `integrated/observations.csv` | 4,809,257 rows from 149 releases of 22 publications (4,649,536 before group 2); 4,538,809 published numbers; `value_flag`: 12,248 `rse_25_to_50`, 2,133 `rse_over_50`, 108 `footnote`, 60 `revised` |
| Latest values | 2,695,147 series × period, each with exactly one `is_latest` |
| `integrated/series.csv` | 769,397 series × 487 columns; every series has a population except 9 Recorded Crime – Victims series; 403 child protection series have no measure (I36); 443 prison health series have no unit (I37) |
| `integrated/measures.csv`, `sources.csv` | 2,565 measures; 9,137 sheets with data |
| Values that can't be told apart (two different numbers) | Crime Victimisation 2,246; Recorded Crime – Victims 1,397; Courts 1,008; Recorded Crime – Offenders 571; Prisoners 315; Youth Justice 129; Federal Defendants 108; partner violence 108; child protection 71; Personal Fraud 11; sexual violence 4; stalking 4; RoGS and the other group 2 publications 0 keys (ISSUES.md I26, I34, I35, I36, I37) |
| Checks | 79 tests; **no `error`-level failures**; 905 warning failures, all known issues (below) |
| Admission | 149 of 721 release switches on (`sources/dataset_selection.json`): every release of the four ABS justice and two ABS victims publications, AIHW Child protection 2020–21 to 2024–25, AIHW Youth Justice 2024–25, RoGS Justice 2020–2026, and the 13 group 2 releases (DECISIONS.md 34). EEH and AIC are off (DECISIONS.md 32, ISSUES.md I37). 10,675 admitted sheets, all with recipes |
| New sources prepared | 689 workbooks downloaded to `source-originals/`, all SHA-matched; 543 converted from XLS (118 with macros), 146 copied; in `source-spreadsheets-xlsx/`. The 6 AIC workbooks couldn't be downloaded by R (I37) |
| CSV size | 1.6 GB in total (observations 1,050 MB, series 497 MB) |

Derived by `harmonise()` (records, before the integration work): `reference_date`
1,728,664; `period` 638,292; `state` 505,204; `court_level` 105,770; `measure` 57,025;
`unit` 48,524; `estimate_type` 21,795.

Run times (see README "Run times and performance"):
- 10,675 sheets (2026-11-03): a change to `harmonise()` or `identify()` with new sheets
  took 40 minutes; a normalisation and harmonisation spec change, 35 minutes.
- 9,040 sheets (2026-11-02): a code change, or a spec edit that touches every sheet, takes
  about 23 minutes (35 before that day's changes), or 11 minutes without the checks
  (`tar_make(names = integrated_files)`).

At 5,209 sheets (2026-11-01):
- a full `tar_make()` after a change to `process_recipe()` takes about 28 minutes;
- one recipe edited: about 3 minutes;
- a measure-spec edit: about 9 minutes;
- rewriting `source_metadata.csv` with no change to any sheet's processing fields takes
  about 15 seconds (8 metadata targets);
- a normalisation spec change takes about 11 minutes;
- a measure or integration spec change takes about 4 minutes. `assemble()` takes
  2 minutes; the other integration targets take seconds.

## Quality checks done

Recipes were compared with the reference database for every batch (scripts in `qa/`):

- Values: 100% match on sampled cells. The only differences are published (rounded)
  values where the database stores unrounded ones.
- Cells: recipes cover every database observation except blank cells (ISSUES.md I5).
- Labels: 98.9-100% of reference labels found as labels or in title/metadata. No
  wrong labels found except the two `court_level` recipes (fixed) and the Prisoners
  2011 publisher duplicate (I9).

Pipeline checks (`tar_read(check_failures)`). Each error-level test was also shown to
fail on deliberately corrupted data. These warnings remain:

| Warning | Where | Issue |
|---|---|---|
| `has_title` | 1 sheet (Recorded Crime – Victims) | I34 |
| `measure_present`, `population_present` | 12 and 1 sheets (child protection; Recorded Crime – Victims) | I34, I36 |
| `series_have_population_and_measure` | 403 child protection series without a measure, 9 Recorded Crime – Victims without a population | I34, I36 |
| `values_distinguishable` | 5,972 keys with two different numbers (as above; group 2 adds 127) | I26, I34, I35, I36, I37 |
| `states_are_canonical` | 877 sheets: ACT prisoner locations (Prisoners), "Total" and "Aust cts" in AIHW and RoGS, youth detention "Aust excl NT" and "Aust incl NT", RoGS "Aus Gov" | I11, I36, I37 |
| `no_stacked_characteristics` | 4 sheets | I12 |
| `reference_dates_present` | 4 sheets: the typos `2022–22` and `Dec 208`, and Youth Justice months without a year | I12, I36 |
| `series_columns_snake_case` | 1 name, `order outcome` | I35 |
| `labels_have_one_spelling` | 90 groups (25 before group 2; the 65 new ones involve its labels) | I35, I37 |
| `none_unrecognised` | 75 texts (`_`, `jki`, `.`, child protection `<0.1`, `>99.9`, and 70 prison health ranges such as `19–57`) | I31, I36, I37 |
| `recipes_outside_selection` | the 237 EEH recipes, now switched off | DECISIONS.md 32 |

Integration stages (2026-11-01):
- `qa/check_integrated.R`: every series, sheet and measure ID resolves, no duplicate
  cells, exactly one `is_latest` per series and period, and every published number
  parsed.
- `qa/blank_cells_vs_reference.R`: blank-cell records have 100% precision against
  the database on 250 sheets, but only 42% recall (ISSUES.md I5).
- `qa/verify_court_cubes.R`: evidence for the old Courts cube → court level mapping.
- `integration_report()` (`tar_read(integration_gaps)`) shows no unrecognised value
  text.

## Waiting on the owner

1. **Set Excel ▸ Settings ▸ Security back** from "Disable all macros without
   notification" (the conversions are done).
2. **Review the 34 victims dictionary names** marked "for owner review" in
   `dictionary/dimensions.csv`, and `dictionary/proposed.csv` (I10).
3. Confirm the overnight judgement calls in ISSUES.md I34: survey estimates without an
   `estimate_type`, CV population rules, value flags.
4. **Review the 59 AIHW and RoGS dictionary names** marked "for owner review", and
   confirm the judgement calls in ISSUES.md I36.
5. Start stage 7, `classify()` (I6, I27)?
6. Confirm the judgement calls in ISSUES.md I28.
7. Git clean-up (I16).
8. Confirm the label consistency judgement calls in ISSUES.md I35.

## Recommended next steps

1. **Owner review of the overnight victims choices** (Waiting on the owner 1–3).
2. **AIHW and RoGS leftovers (I36):** the remaining gaps, and the label consistency seed
   applied to their labels.
3. **`classify()` (stage 7).** Add `is_total` and parents, and fill implicit totals (I27,
   including estimates without an `estimate_type`).
4. **Clear the remaining identity conflicts (I26, I34)** with
   `qa/integration_conflicts.R`. Crime Victimisation's within-sheet ones need recipe
   fixes.
5. **Recipe support for blank rows (I5).**
6. **Admit further releases progressively (`sources/README.md`).** Use the victims
   workflow as the template:
   - pilot, then add dictionary names for repeated new dimensions;
   - full run;
   - `qa/stage_sheets.R` to list contradictions before the rebuild;
   - a seed script for the publication's spec entries.

## Git and GitHub

**Published 2026-11-02:** https://github.com/ianmoran11/tidy-pipeline (public, MIT; data
CC BY 4.0, see `DATA-LICENSE.md`).
- Release `v2026-11-02` (marked latest) holds the zipped integrated CSVs (160 MB) and their
  SHA-256.
- Release `sources-2026-11-02` (not marked latest, so the README's "latest release" link
  stays on the dataset) holds the zipped source XLSX: 1,199 workbooks plus 76
  reference-only copies, `MANIFEST.csv`, `source_metadata.csv`; 146 MB.
- The published history is the local history with the reference database, its `.gz`,
  `source-spreadsheets-xlsx.zip`, `_targets/`, `.DS_Store` and the Excel lock file
  removed from every commit (`git filter-repo`), because GitHub rejects files over
  100 MB. Its files are identical to the local commits; only the commit IDs differ.
- The local repository still has those files in its history, so it can't push to GitHub
  directly. Until it is switched onto the published history, publish new commits like
  this:
  1. bare-clone the local repo (`git clone --bare --no-local`);
  2. run the same `git filter-repo` command (it's deterministic, so earlier commits keep
     their published IDs);
  3. push `main` (a fast-forward).

  `../tidy-pipeline-publish.git` is the last filtered copy.
