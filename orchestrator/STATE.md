# State at handover (2026-11-02, after the label consistency work)

## Corpus

| | Count |
|---|---|
| Workbooks in `source-spreadsheets-xlsx/` (active) | 1,199 (545 from the original package, 654 prepared from the national catalogue) |
| Archived reference-only copies (`reference-only/`) | 76 (608 sheets) |
| Sheets in `source_metadata.csv` | 10,902 |
| Active sheets | 10,294, of which 9,304 are in switched-on releases |

## Recipes

9,040 recipes: 7,591 data, 970 contents, 479 notes:
- 3,256 for the original package's active sheets;
- 1,953 for the new ABS justice releases (2026-11-01);
- 3,831 for the two ABS victims publications (2026-11-01/02).

| Status | Count | Note |
|---|---|---|
| validated | 8,258 | |
| needs_review | 782 | 557 contents and 222 notes are the validator's false alarm on numbers in non-data sheets (ISSUES.md I7); 3 data have isolated numbers outside their tables (I8) |

Admitted sheets (switched-on releases) by publication:

| Publication | Admitted sheets | Recipes | Left |
|---|---|---|---|
| crime-victimisation-australia | 2,501 | 2,501 |   0 |
| criminal-courts-australia | 2,101 | 2,101 |   0 |
| recorded-crime-victims | 1,330 | 1,330 |   0 |
| prisoners-australia | 1,257 | 1,257 |   0 |
| recorded-crime-offenders | 1,058 | 1,058 |   0 |
| federal-defendants-australia |   402 |   402 |   0 |
| employee-earnings-hours-australia |   329 |   237 |  92 |
| aihw-youth-justice-australia |   161 |    47 | 114 |
| pc-report-on-government-services-justice |    86 |    28 |  58 |
| aihw-child-protection-australia |    79 |    79 |   0 |
| **Total** | **9,304** | **9,040** | **264** |

`agents/queue.csv` (switched-on releases only): 1,159 workbooks, 1,143 done, 264 sheets left (Youth Justice 2024–25, EEH May 2021, RoGS 2020).

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
| Victims publications, pilot | `agents/batch-victims-pilot.txt` | 239 | 10 min | $4.15 |
| Victims publications, the rest | `agents/batch-victims-rest.txt` | 3,592 | 2 h 11 min | $61.28 |
| **All runs** | `agents/runs.csv` | | | **$173.84** (1,146 runs) |

Costs are Pi's estimates at API prices; on the owner's ChatGPT plan they draw on
subscription allowance instead.

## Pipeline outputs

| Target | Value |
|---|---|
| `data` | 9,040 sheets (every admitted sheet with a recipe) |
| `data_normalised`, `data_harmonised`, `data_identified` | same records; every record has `period`; 236 lack `reference_date` (the publisher typos `2022–22` and `Dec 208`, ISSUES.md I12) |
| `integrated/observations.csv` | 3,989,690 rows from 129 releases (2,628,052 before the victims publications); 3,870,414 published numbers; `value_flag`: 8,909 `rse_25_to_50`, 1,223 `rse_over_50`, 108 `footnote`, 60 `revised` |
| Latest values | 2,259,337 series × period, each with exactly one `is_latest` |
| `integrated/series.csv` | 661,477 series × 188 columns; every series except AIHW (I1, I25) and 9 Recorded Crime – Victims series has population and measure |
| `integrated/measures.csv`, `sources.csv` | 1,101 measures; 7,591 sheets with data |
| Values that can't be told apart (two different numbers) | Crime Victimisation 2,246; Recorded Crime – Victims 1,397; Courts 1,008; Recorded Crime – Offenders 571; Prisoners 315; Federal Defendants 108; RoGS 13 keys; AIHW about 4,300 (ISSUES.md I26, I34, I35) |
| Checks | 79 tests; **no `error`-level failures**; 633 warning failures, all known issues (below) |
| Admission | 129 of 721 release switches on (`sources/dataset_selection.json`): every release of the four ABS justice and two ABS victims publications, plus the original 59. 9,304 admitted sheets, 9,040 with recipes. Without recipes: Youth Justice 2024–25 (114), EEH May 2021 (92), RoGS 2020 (58) |
| New sources prepared | 654 workbooks downloaded to `source-originals/`, all SHA-matched; 543 converted from XLS (118 with macros), 111 copied; in `source-spreadsheets-xlsx/` |
| CSV size | 1.1 GB in total (observations 865 MB, series 226 MB) |

Derived by `harmonise()` (records, before the integration work): `reference_date`
1,728,664; `period` 638,292; `state` 505,204; `court_level` 105,770; `measure` 57,025;
`unit` 48,524; `estimate_type` 21,795.

Run times (see README "Run times and performance"):
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
| `has_title` | 111 sheets | I25 (early AIHW recipes) |
| `measure_present`, `population_present` | 53 and 98 sheets, about 15,900 and 22,700 records | I1, I25 |
| `series_have_population_and_measure` | 8,498 series (AIHW, plus 9 Recorded Crime – Victims) | I1, I25 |
| `values_distinguishable` | 9,988 keys (AIHW 4,330; Crime Victimisation 2,246; Recorded Crime – Victims 1,397; Courts 1,008; Recorded Crime – Offenders 571; Prisoners 315; Federal Defendants 108; RoGS 13) | I26, I34, I35 |
| `states_are_canonical` | 359 sheets, 767 labels (mostly ACT prisoner locations) | I11 |
| `no_stacked_characteristics` | 4 sheets | I12 |
| `reference_dates_present` | 2 sheets (2 period labels) | I12 |
| `series_columns_snake_case` | 1 name, `order outcome` | I35 |
| `labels_have_one_spelling` | 25 groups | I35 |
| `none_unrecognised` | 3 texts (`_`, `jki`, `.`) | I31 |
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

1. **Set Excel ▸ Settings ▸ Security back** from "Disable all macros without
   notification" (the conversions are done).
2. **Review the 34 victims dictionary names** marked "for owner review" in
   `dictionary/dimensions.csv`, and `dictionary/proposed.csv` (I10).
3. Confirm the overnight judgement calls in ISSUES.md I34: survey estimates without an
   `estimate_type`, CV population rules, value flags.
4. Rerun the agents on the 181 early recipes? About $4; it fixes I3 and I25 (AIHW
   titles).
5. Start stage 7, `classify()` (I6, I27)?
6. Confirm the judgement calls in ISSUES.md I28.
7. Git clean-up (I16).
8. Confirm the label consistency judgement calls in ISSUES.md I35.

## Recommended next steps

1. **Owner review of the overnight victims choices** (Waiting on the owner 1–3).
2. **Fix the early recipes (I3, I25), if the owner agrees.** Then add AIHW subjects to
   `measures/measure_spec.json`, rebuild, and check `integration_gaps`.
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
