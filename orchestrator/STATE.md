# State at handover (2026-11-01, after the integration stages)

## Corpus

| | Count |
|---|---|
| Workbooks in `source-spreadsheets-xlsx/` (active) | 545 |
| Archived reference-only copies (`reference-only/`) | 76 (608 sheets) |
| Sheets in `source_metadata.csv` | 5,118 |
| Active sheets | 4,510 |

## Recipes

5,209 recipes: 4,514 data, 622 contents, 73 notes. That's 3,256 for the original
package's active sheets plus 1,953 for the new ABS justice releases (2026-11-01).

| Status | Count | Note |
|---|---|---|
| validated | 4,841 | |
| needs_review | 368 | 364 contents and 1 notes are the validator's table-number false alarm (ISSUES.md I7); 3 data have isolated numbers outside their tables (I8) |

Admitted sheets (switched-on releases) by publication:

| Publication | Admitted sheets | Recipes | Left |
|---|---|---|---|
| criminal-courts-australia | 2,101 | 2,101 |   0 |
| prisoners-australia | 1,257 | 1,257 |   0 |
| recorded-crime-offenders | 1,058 | 1,058 |   0 |
| federal-defendants-australia |   402 |   402 |   0 |
| employee-earnings-hours-australia |   329 |   237 |  92 |
| aihw-youth-justice-australia |   161 |    47 | 114 |
| pc-report-on-government-services-justice |    86 |    28 |  58 |
| aihw-child-protection-australia |    79 |    79 |   0 |
| **Total** | **5,473** | **5,209** | **264** |

`agents/queue.csv` (switched-on releases only): 763 workbooks, 747 done, 264 sheets left (Youth Justice 2024–25, EEH May 2021, RoGS 2020).

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
| New ABS justice releases, pilot (2001 → 2019-20, all 4 publications) | `agents/batch-abs-new-pilot.txt` | 243 | 12 min | $5.99 |
| New ABS justice releases, the rest | `agents/batch-abs-new-rest.txt` | 1,710 | 48 min | $35.05 |
| **All runs** | `agents/runs.csv` | | | **$108.41** (750 runs) |

Costs are Pi's estimates at API prices; on the owner's ChatGPT plan they draw on
subscription allowance instead.

## Pipeline outputs

| Target | Value |
|---|---|
| `data` | 3,256 sheets, 1,752,195 records: 1,728,900 non-blank values and 23,295 blank cells (`.value` NA) |
| `data_normalised`, `data_harmonised`, `data_identified` | same records; every record has `period`; 236 lack `reference_date` (2 typo labels) |
| `integrated/observations.csv` | 2,628,052 rows (after the new ABS releases; 1,752,195 before) |
| Latest values | 1,731,063 series × period, each with exactly one `is_latest` |
| `integrated/series.csv` | 582,585 series; 69 populations; every ABS/RoGS series has population and measure (AIHW doesn't: ISSUES.md I1, I25) |
| `integrated/measures.csv`, `sources.csv` | 681 measures; 2,778 sheets with data from 59 releases |
| Values that can't be told apart (two different numbers) | Courts 782, Recorded Crime 185, Prisoners 160, Federal Defendants 107, RoGS 13 keys; AIHW about 4,300 (ISSUES.md I26) |
| Checks | 77 tests; **no `error`-level failures**; 459 warning failures, all known issues (below) |
| Admission | 90 of 721 release switches on (`sources/dataset_selection.json`): every release of the four ABS justice publications, plus the original 59. 5,473 admitted sheets, 5,209 with recipes. All ABS justice sheets are covered. Without recipes: Youth Justice 2024–25 (114), EEH May 2021 (92), RoGS 2020 (58) |
| New sources prepared | 258 workbooks (73 MB) downloaded to `source-originals/`, all SHA-matched; 241 converted from XLS (50 with macros), 17 copied; in `source-spreadsheets-xlsx/` |
| CSV size | 708 MB in total (observations 558 MB, series 163 MB) |

Derived by `harmonise()` (records, before the integration work): `reference_date`
1,728,664; `period` 638,292; `state` 505,204; `court_level` 105,770; `measure` 57,025;
`unit` 48,524; `estimate_type` 21,795.

Run times:
- a full `tar_make()` after a change to `process_recipe()` takes about 40–45 minutes
  with the checks;
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
| `has_title` | 110 sheets | I25 (early AIHW recipes) |
| `measure_present`, `population_present` | 53 and 97 sheets, about 15,900 and 22,500 records | I1, I25 |
| `series_have_population_and_measure` | 8,489 series | I1, I25 |
| `values_distinguishable` | 4,609 keys (AIHW 4,330; Prisoners 144; Courts 87; Recorded Crime 35; RoGS 13) | I26 |
| `states_are_canonical` | 180 sheets, 322 labels | I11 |
| `no_stacked_characteristics` | 4 sheets | I12 |
| `reference_dates_present` | 2 sheets (`2022–22`, `Dec 208`) | I12 |
| `names_are_snake_case`, `series_columns_snake_case` | 7 names | I3, I10 |
| `labels_have_no_footnote_markers` | 3 labels, e.g. "Total guilty outcome(h)(l)" | I11 |
| `selected_sheets_have_recipes` | 3 partially covered releases | I31 |

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
4. Git clean-up (I16). New since: `source-originals/` (73 MB) and 258 new XLSX in
   `source-spreadsheets-xlsx/`.

## Recommended next steps

1. **Fix the early recipes (I3, I25), if the owner agrees.** Then add AIHW subjects to
   `measures/measure_spec.json`, rebuild, and check `integration_gaps`.
2. **`classify()` (stage 7).** Add `is_total` and parents, and fill implicit totals
   (I27), so `is_latest` gives one row per real quantity.
3. **Clear the remaining ABS identity conflicts (I26)** with
   `qa/integration_conflicts.R`.
4. **Recipe support for blank rows (I5),** before many new recipes are written, so they
   include blank rows from the start.
5. **Admit new releases progressively (`sources/README.md`, I31).** For each:
   - switch it on and run `Rscript get_source_data.R`;
   - check `sources/preparation_report.csv`;
   - run agent batches (only switched-on releases are queued);
   - extend the specs, then `tar_make()`.

   Pilot each new publication and review it with `qa/` first. 264 sheets in releases
   already switched on still lack recipes (I2).

## Git

Three commits by the owner:
- `35a2a6b`: tidying, normalising, harmonising;
- `580c4f7`: the integration stages and the orchestrator folder;
- `9b550de` "tests": the check functions and the spec fixes they found.

All three include the large and stray files listed in ISSUES.md I16. Uncommitted since
`9b550de` (source selection, 2026-11-01 afternoon):
- **New:** `sources/` (selection JSON, pinned catalogues, README, Excel conversion script,
  `preparation_report.csv`), `get_source_data.R` (rewritten; the old version moved to
  `sources/build_current_catalogue.R`), `R/select_sheets.R`,
  `R/check_selected_sheets.R`.
- **Modified:**
  - `_targets.R`, `agents/queue.R`, `R/check_source_metadata.R`;
  - `source_metadata.csv` (now with `release_key` and `catalogue`, sorted);
  - `orchestrator/` docs.
