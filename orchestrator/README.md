# Orchestrator handover

This folder is the handover for whoever orchestrates this project next (a person or
an agent). It records what was built, why, what state it is in, and what is still
open. Written 2026-11-01; updated the same day after the integration stages were built.

Read in this order:

1. this README: what the project is and how the parts fit together;
2. [`STATE.md`](STATE.md): numbers as of the handover, what is waiting on the owner, and
   the recommended next steps;
3. [`ISSUES.md`](ISSUES.md): everything known to be unresolved, by priority;
4. [`DECISIONS.md`](DECISIONS.md): decisions the project owner made, so they are not
   re-litigated;
5. [`DATA-NOTES.md`](DATA-NOTES.md): facts about the source spreadsheets and the
   reference database that were expensive to discover;
6. [`qa/README.md`](qa/README.md): review scripts used to check agent output against
   the database.

## What the project does

It turns 545 published statistics workbooks (ABS, AIHW, Productivity Commission;
4,510 sheets) into tidy records: one record per published value, with every dimension
needed to interpret it. The end product is an **integrated dataset for analysis**: four
linked CSV tables in `integrated/` (observations, series, measures, sources). Each sheet gets a JSON *recipe* that says where its values and
labels are. Recipes are written by headless LLM agents (Pi coding agent, ChatGPT
models), checked by a validator, then run through a `targets` pipeline that extracts,
normalises and harmonises the records.

## Pipeline (`_targets.R`)

```
source_metadata.csv ─┐
tidy-recipes/*.json ─┴─> data              process_recipe()   one branch per recipe
                          └─> data_normalised   normalise()        normalisation/normalisation_spec.json
                               └─> data_harmonised  harmonise()    harmonisation/harmonisation_spec.json
                                    ├─> harmonisation_gaps  harmonisation_report()
                                    └─> data_identified  identify()   measures/measure_spec.json
                                         └─> integrated  assemble()      integration/integration_spec.json
                                              └─> observations_typed  type_values()  integration/value_spec.json
                                                   └─> observations  reconcile()     integration/reconcile_spec.json
                                                        ├─> integrated_files  write_integrated()  integrated/*.csv
                                                        └─> integration_gaps  integration_report()
```

- **`process_recipe()`** (`R/process_recipe.R`) reads the sheet with tidyxl and returns
  `list(sheet_metata, tables, source)`. `tables` holds, per table, `tidy_table_list`
  (records: `row`, `col`, `address`, `.value` and one field per header) and
  `meta_data_list` (table-level labels). `.value` is the *published* value: numbers
  are rounded as Excel displays them (`R/published_value.R`). Empty cells inside a
  table's value grid become records with `.value` NA (`R/blank_value_cells.R`). `source` has the sheet
  ID, publication and release reference period. `sheet_metata` is a typo kept for
  compatibility.
- **`normalise()`** (`R/normalise.R`, 30 lines) renames dimensions and replaces label
  text from the JSON spec (`dimension_names`, then `values` per dimension).
- **`harmonise()`** (`R/harmonise.R`, 49 lines) makes each record self-contained: copies
  table labels onto records, unstacks old characteristic/category pairs, splits
  compound labels, takes missing dimensions from the title, falls back to the
  release period, and adds `reference_date`. See `harmonisation/README.md`.
- **`harmonisation_report()`** lists what is still missing (`tar_read(harmonisation_gaps)`).
- **`identify()`** (`R/identify.R`) adds what each record counts (`population`,
  `scope`, `measure`, …) from the title's subject, the subtitle and the unit. See
  `measures/README.md`.
- **`assemble()`, `type_values()`, `reconcile()`** turn the sheets into the integrated
  dataset: `observations`, `series`, `measures` and `sources`, with numeric values,
  value statuses and every release's value (the latest flagged). It's written to
  `integrated/*.csv`. See `integration/README.md`, which is also the data dictionary.
  `tar_read(integration_gaps)` reports values that can't be told apart and series
  without a population or measure.

## Checks

Every data target has one check function (`R/check_<target>.R`) and a `<target>_checks`
target. Inside each function, every test is its own nested function that returns its
failures (nothing when it passes). A named `severity` vector lists the tests.

| Severity | Meaning | On failure |
|---|---|---|
| `error` | An invariant that must always hold, e.g. a stage changed no values, cells are unique, links resolve, one `is_latest` per series and period | The check target stops, naming the test and the first failures |
| `warning` | An expectation with known exceptions, e.g. AIHW records without a measure | Reported only |

Each check returns one row per test: `target`, `sheet_sha256`, `test`, `severity`,
`passed`, `n_failed`, `examples`.

- **Per-sheet targets** (`data` … `data_identified`) are checked branch by branch
  (`pattern = map(...)`), each against the branch it came from. Agent batches only
  re-check the sheets they change.
- **Failed checks don't hold up the build.** Check targets use `error = "continue"`, so
  `tar_make()` finishes and lists them as errored targets.
- **`tar_read(check_failures)`** has every failed test, warnings included.

To add a test, add a nested function and a `severity` entry. Remember that
`paste("x", character(0))` returns `"x "`, so build failure messages with `sprintf()`.

| Target | Check | Tests |
|---|---|---|
| `source_metadata_df` | `check_source_metadata()` | 7: columns, unique IDs, IDs match exact sheet names (catches trimming), workbooks exist, sheet positions, publications, archived copies point to active sheets |
| `data` | `check_data()` | 10: shape, sheet active, matches recipe kind and record count, addresses, unique cells, single-text labels, every record labelled, published text (no `1e+05`), title present |
| `data_normalised` | `check_data_normalised()` | 7: same shape and cells as `data`, no unmapped names or labels left (catches chains in the spec), single-text labels, snake_case names, footnote markers |
| `data_harmonised` | `check_data_harmonised()` | 9: same shape and cells, period present, valid ISO dates, dates present, `.derived` consistent, single-text labels, no characteristic/category left, canonical states |
| `data_identified` | `check_data_identified()` | 7: same shape and cells, existing labels kept, added fields in `.derived`, measure and population present, title subject in the spec |
| `integrated` | `check_integrated()` | 10: columns, one row per record, unique cells and IDs, well-formed IDs, links resolve, periods and dates, series and sources complete, population and measure present, snake_case columns |
| `observations_typed` | `check_observations_typed()` | 7: rows unchanged, statuses allowed, none unrecognised, numbers equal their text, blanks consistent, symbol values from the spec, finite values |
| `observations` | `check_observations()` | 6: rows unchanged, releases present, one latest per series and period, `n_releases` right, revision flags consistent, values distinguishable |
| `integrated_files` | `check_integrated_files()` | 5: files exist, columns and row counts match, observations round-trip, no `NA` text |

The checks add about 7 minutes of branch time to a full rebuild. `check_observations()`
takes 28 seconds; the other whole-table checks take seconds.

## Run times

All specs are hand-edited JSON. Editing a spec reruns only the stages after it:
- the normalisation spec takes about 11 minutes;
- the measure or integration specs take about 4 minutes.

Changing `process_recipe()` or anything it calls (`one_enhead()`,
`blank_value_cells()`, `published_value()`) rebuilds everything, which takes about
30 minutes for 3,256 recipes.

`source_metadata.csv` is produced by `get_source_data.R` (one row per sheet; see
`DATA-NOTES.md`). The script builds `source_data_df_04` but does not write the CSV:
run `source("get_source_data.R"); readr::write_csv(source_data_df_04, "source_metadata.csv")`.

## Recipes

- One file per sheet: `tidy-recipes/<sheet_sha256>.json`, where
  `sheet_sha256 = sha256("<original workbook sha256>/<exact sheet name>")`.
- Format v0.2: `schema/recipe-v0.2.json` and
  `agents/skills/tidy-recipe-authoring/references/recipe-format.md`. Key fields:
  `kind` (data/contents/notes/empty/unsupported), `status` (draft/validated/
  needs_review, set only by `submit_recipe`), `meta_data`, `tables` (each with
  `range`, `values_range`, `headers` with unpivotr directions, `meta_data`),
  `new_dimensions`, `caption`, `validation`, `generation` (agent settings and the
  exact prompt that produced the recipe).
- Dimension names come from `dictionary/dimensions.csv` (snake_case, aliases, names to
  avoid). The publisher's wording goes in `caption`. Agents declare names the
  dictionary lacks in `new_dimensions`; `Rscript agents/dictionary.R report` collects
  them into `dictionary/proposed.csv` for review.

## Agent system

| Part | Where |
|---|---|
| Tools (R CLI): `list_workbook_sheets`, `sheet_grid`, `find_template_recipes`, `validate_recipe`, `run_recipe`, `submit_recipe` | `agents/tools/recipe_tools.R` |
| Pi extension: registers the tools for codemode, write gate (`RECIPE_ALLOWED_SHAS`), generation record (`RECIPE_RUN_MANIFEST`), fast mode (`RECIPE_FAST=1`) | `agents/extension/recipe-tools.ts` |
| Skill: workflow, rules, format, layouts, naming guide, two example recipes | `agents/skills/tidy-recipe-authoring/` |
| Prompts: worker (used), reviewer (written, no driver yet) | `agents/prompts/` |
| Queue, prompt rendering, run records, cost summary | `agents/queue.R` |
| One workbook / many in parallel | `agents/run_one.sh`, `agents/run_agents.sh` |
| Batch progress and provider errors | `agents/batch_status.R` |
| Readable trace of one run | `agents/show_log.py` |

The validator (`validate_recipe`, `run_recipe`, `submit_recipe`) enforces: v0.2
fields, exact sheet name, cell references inside the sheet, header directions, no
header/value overlap, no meta_data on value cells, dictionary names, and coverage
(no blank values, every non-blank cell in a table's range used, every record
labelled, no value cell in two tables, no numbers outside tables). It checks
structure, not whether labels are right: see ISSUES.md I4.

### Running agents

```bash
Rscript agents/queue.R build                               # refresh agents/queue.csv
agents/run_agents.sh -j 6 -n 20                            # next 20 unfinished workbooks
agents/run_agents.sh -j 6 $(cat my-list.txt)               # specific workbooks
RECIPE_MODEL=openai-codex/gpt-6.1-sol RECIPE_THINKING=medium agents/run_one.sh <xlsx_file>
Rscript agents/batch_status.R my-list.txt                  # progress while running
Rscript agents/queue.R costs                               # tokens and estimated cost per run
Rscript agents/dictionary.R report                         # new and non-dictionary names
```

Defaults: model `openai-codex/gpt-6.1-sol`, thinking `medium`, normal tier, 6 in
parallel (no rate limiting seen). One run per workbook; the prompt lists only sheets
without a validated or needs_review recipe, so reruns are safe. Each run writes
`agents/runs/<run_id>.json` (settings and prompt) and `agents/logs/<run_id>.jsonl`
(1.2 GB so far, gitignored). About 31-42 minutes and $21-23 (Pi's API-price
estimate) per 1,000 sheets.

How the three ABS batches were picked: `qa/select_batch.R`.

## Pitfalls already hit (do not rediscover)

- **tidyxl's numeric sheet index is not the tab order.** Always read sheets by name.
- **`readr::read_csv()` trims whitespace by default.** Ten sheet names end in a space
  (`"Table 80 "`), so read `source_metadata.csv` with `trim_ws = FALSE` everywhere.
- **R's `$` partially matches list names.** `rule$value` returned a rule's whole
  `values` list. Use `[[ ]]` for spec and record lookups.
- **`as.character(numeric)` is the stored value**, not the published one, and gives
  `"1e+05"`. R's `round()` is not Excel's (round half to even). tidyxl 1.0.10
  misreports Excel's built-in formats 3, 4 and 37-40 (`#;##0.00` for `#,##0.00`).
  All handled in `R/published_value.R`.
- **Pi `--tools` is an allowlist.** Extension tools must be named in it or codemode
  cannot see them.
- **`tibble(x = nrow(x), ...)` masks `x`** for later arguments (bit several review
  scripts).
- **`format()` on a numeric vector pads every element** to the longest decimals; use
  `sprintf("%.15g")` per element.
- **Excel lock files (`~$…xlsx`)** appear in the source folder when a workbook is open
  in Excel. `get_source_data.R` skips them.
- **Files open in the owner's editor were overwritten twice** after being edited here.
  Ask the owner to reload before saving.
- **The reference database is not ground truth.** It has its own label errors (see
  DATA-NOTES.md). Adjudicate disagreements against the sheet.
- **"validated" means structurally complete,** not correct.
- **Subtitles name the release period** ("Recorded Crime - Offenders, 2010–11"). Never
  let the subtitle vote alongside the title: read the title first, then the subtitle
  only for anything still missing (`harmonise()` does this now).
- **Title rules need exactly one distinct match.** Two different matches mean the rule
  is skipped silently, and the release period fills in instead.
- **A missing dimension means "total".** `sex` empty and `sex = "Persons"` are the same
  thing but different series (ISSUES.md I27).
- **`summarise()` columns mask later arguments too.** `summarise(x = sum(!is.na(x)),
  y = ... x ...)` sees the new `x`.
- **Rewriting `source_metadata.csv`, even with the same rows reordered, rebuilds
  everything,** because it's a `format = "file"` target. Expect about 27 minutes.
- **Sheets without a value change don't rerun downstream.** `targets` compares branch
  outputs, so a `process_recipe()` change that alters only some sheets reruns only
  their downstream branches.
- **tidyxl omits truly empty cells.** Blank value cells have to be generated from the
  table grid (`R/blank_value_cells.R`), not read.
- **`paste()` and `paste0()` with a zero-length vector return a string** (`"x "`), not
  nothing. Use `sprintf()` when building lists of failures.
- **`!` binds more loosely than `%in%`.** `!(a == b) %in% FALSE` means
  `!((a == b) %in% FALSE)`.
- **`normalise()` makes one pass.** A spec entry whose target is itself a key (e.g.
  "Total prisoners (b)" → "Total prisoners" → …) leaves the middle label behind.
  `check_data_normalised()` catches this.
- **A "Total" label in a population column means that table's population.** Normalise
  it to "Total" and let `identify()`'s `replace_labels` substitute the title's subject.
  Mapping it to one fixed population is wrong for tables of a sub-population (Federal
  prisoners).

## History in one paragraph

Built a metadata table for every sheet, then a recipe format, a validator and a Pi
agent harness. Piloted on 16 workbooks, then reviewed the recipes against the
reference database: no wrong labels found, but naming was inconsistent, periods were
often only in titles, and AIHW values were unrounded. Added published values, a
dimension dictionary, run provenance (`generation`), fast mode, and archived 76
redundant workbook copies. Ran three ABS batches (3,048 sheets; all ABS except EEH done)
and checked each against the database. Added normalisation and harmonisation stages.
Fixed along the way: wrong sheet read by index, trailing-space sheet names, two recipes
taking `court_level` from value cells, and a partial-matching bug in `harmonise()`.
Then built the integration stages (identify, assemble, type_values, reconcile) with
CSV output. Fixed: subtitles outvoting title periods, court levels hidden in old cube
codes, and blank cells inside tables now kept as records.
