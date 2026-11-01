# State at handover (2026-11-01, after the integration stages)

## Corpus

| | Count |
|---|---|
| Workbooks in `source-spreadsheets-xlsx/` (active) | 545 |
| Archived reference-only copies (`reference-only/`) | 76 (608 sheets) |
| Sheets in `source_metadata.csv` | 5,118 |
| Active sheets | 4,510 |

## Recipes

3,256 recipes (all active sheets of the finished workbooks): 2,778 data, 419
contents, 59 notes.

| Status | Count | Note |
|---|---|---|
| validated | 3,033 | |
| needs_review | 223 | 221 contents and 1 notes are the validator's table-number false alarm (ISSUES.md I7); 1 data is Criminal Courts 2023–24 cube 10, Table 53 (I8) |

| Publication | Active sheets | Recipes | Left |
|---|---|---|---|
| criminal-courts-australia | 1,012 | 1,012 | 0 |
| prisoners-australia | 1,002 | 1,002 | 0 |
| recorded-crime-offenders | 653 | 653 | 0 |
| federal-defendants-australia | 198 | 198 | 0 |
| employee-earnings-hours-australia | 329 | 237 | 92 (deferred by owner) |
| aihw-child-protection-australia | 519 | 79 | 440 |
| aihw-youth-justice-australia | 161 | 47 | 114 |
| pc-report-on-government-services-justice | 636 | 28 | 608 |
| **Total** | **4,510** | **3,256** | **1,254** |

`agents/queue.csv`: 545 workbooks, 489 done.

208 recipes come from the pilot and tests (2026-10-31) and predate the dimension
dictionary; 181 of them fail today's validator, on naming only (ISSUES.md I3). The
rest were written after it.

## Agent runs

| Batch | List | Sheets | Wall clock | Est. cost (API prices) |
|---|---|---|---|---|
| Pilot + tests | — | ~210 | — | ~$3 |
| ABS 2025 → 2021-22 | `agents/batch-abs-1000.txt` | 1,005 | 31 min | $20.67 |
| ABS 2021-22 → 2014-15 (no EEH) | `agents/batch-abs-1000-b.txt` | 1,000 | 31 min | $20.76 |
| ABS 2014-15 → 2006 (no EEH) | `agents/batch-abs-rest.txt` | 1,043 | 42 min | $23.06 |
| **All runs** | `agents/runs.csv` | | | **$67.37** (492 runs) |

Costs are Pi's estimates at API prices; on the owner's ChatGPT plan they draw on
subscription allowance instead.

## Pipeline outputs

| Target | Value |
|---|---|
| `data` | 3,256 sheets, 1,752,195 records: 1,728,900 non-blank values and 23,295 blank cells (`.value` NA) |
| `data_normalised`, `data_harmonised`, `data_identified` | same records; every record has `period`; 236 lack `reference_date` (2 typo labels) |
| `integrated/observations.csv` | 1,752,195 rows. Statuses: published 1,701,188; blank 23,295; not published 11,948; not available 10,265; not applicable 3,008; nil or rounded to zero 2,491 |
| Latest values | 1,170,236 series × period, each with exactly one `is_latest`; 256,524 are published in 2+ releases; 99,214 older values differ from the latest (revisions) |
| `integrated/series.csv` | 382,398 series × 114 columns; 69 populations; every ABS/RoGS series has population and measure (AIHW doesn't: ISSUES.md I1, I25) |
| `integrated/measures.csv`, `sources.csv` | 681 measures; 2,778 sheets with data from 59 releases |
| Values that can't be told apart | ABS: Prisoners 144, Courts 87, Recorded Crime 35, RoGS 13 keys; AIHW about 4,300 (ISSUES.md I26) |
| Checks | 68 tests, 107,483 results; **no `error`-level failures**; 458 warning failures, all known issues (below) |
| CSV size | 467 MB in total (observations 369 MB, series 102 MB) |

Derived by `harmonise()` (records, before the integration work): `reference_date`
1,728,664; `period` 638,292; `state` 505,204; `court_level` 105,770; `measure` 57,025;
`unit` 48,524; `estimate_type` 21,795.

Run times:
- a full `tar_make()` after a change to `process_recipe()` takes about 27 minutes;
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
| `has_title` | 110 sheets | I25 (early AIHW recipes) |
| `measure_present`, `population_present` | 53 and 97 sheets, about 15,900 and 22,500 records | I1, I25 |
| `series_have_population_and_measure` | 8,489 series | I1, I25 |
| `values_distinguishable` | 4,609 keys (AIHW 4,330; Prisoners 144; Courts 87; Recorded Crime 35; RoGS 13) | I26 |
| `states_are_canonical` | 180 sheets, 322 labels | I11 |
| `no_stacked_characteristics` | 4 sheets | I12 |
| `reference_dates_present` | 2 sheets (`2022–22`, `Dec 208`) | I12 |
| `names_are_snake_case`, `series_columns_snake_case` | 7 names | I3, I10 |
| `labels_have_no_footnote_markers` | 3 labels, e.g. "Total guilty outcome(h)(l)" | I11 |

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

1. Rerun the agents on the 181 early recipes? About $4; it fixes I3 and I25 (AIHW
   titles).
2. Start stage 7, `classify()` (I6, I27)?
3. Confirm the judgement calls in ISSUES.md I28.
4. Git clean-up (I16).

## Recommended next steps

1. **Fix the early recipes (I3, I25), if the owner agrees.** Then add AIHW subjects to
   `measures/measure_spec.json`, rebuild, and check `integration_gaps`.
2. **`classify()` (stage 7).** Add `is_total` and parents, and fill implicit totals
   (I27), so `is_latest` gives one row per real quantity.
3. **Clear the remaining ABS identity conflicts (I26)** with
   `qa/integration_conflicts.R`.
4. **Recipe support for blank rows (I5),** before the remaining 1,254 sheets (I2) are
   run, so new recipes include them from the start.
5. **Agent batches for AIHW child protection, Youth Justice, RoGS and EEH (I2).** Pilot
   each publication and review it with `qa/` first.

## Git

Two commits by the owner:
- `35a2a6b` first commit: tidying, normalising, harmonising;
- `580c4f7` (2026-11-01 10:13): the integration stages and the orchestrator folder.

Both include the large and stray files listed in ISSUES.md I16. Uncommitted since
`580c4f7`:
- the check functions (`R/check_*.R`) and their targets in `_targets.R`;
- spec fixes found by the checks (R15, R16): `normalisation/normalisation_spec.json`,
  `measures/measure_spec.json`;
- doc updates in `orchestrator/` (including `qa/README.md`) and `measures/README.md`.
