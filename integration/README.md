# Integrated dataset

The last stages of the pipeline turn the per-sheet records into four linked tables,
written as CSV to `integrated/` (gitignored; rebuild with `targets::tar_make()`):

```
data_identified ─> assembled            assemble_sheet()  one branch per sheet: records → columns
               └─> integrated           assemble()      integration_spec.json
                    └─> observations_typed  type_values()   value_spec.json
                         └─> observations      reconcile()     reconcile_spec.json
                              ├─> integrated_files   write_integrated()   integrated/*.csv
                              └─> integration_gaps   integration_report()
```

## Tables

All files are UTF-8 CSV. Missing values are empty fields.

### `observations.csv`: one row per published value

| Column | Meaning |
|---|---|
| `series_id` | The series the value belongs to (`series/<publication_id>.csv`) |
| `period` | Period, with one spelling for each: `2023–24`, `May 2023`, `June quarter 2026`, `2014`, `2019–21`. A plain year is a calendar year in Recorded Crime – Victims, RoGS Justice and youth justice, Corrective Services and the Personal Safety surveys, and 30 June in Prisoners, child protection and prison health (`harmonisation/README.md`) |
| `reference_date` | ISO date the period ends, e.g. `2024-06-30` |
| `value` | The number, rounded as published. A cell formatted as a percentage is the percentage Excel shows (`-20.4`, not the stored `-0.204`). Symbols that mean nil or rounded to zero are `0`; other symbols and blanks are empty |
| `value_status` | `published`, `blank` (empty cell in the published table), `not_published` (including BOCSAR's `1 to 4`, counts between 1 and 4 suppressed for privacy), `not_available`, `not_applicable`, `nil_or_rounded_to_zero`, `not_calculated` (BOCSAR's `nc`: too few incidents or too small a population), `no_significant_trend` (BOCSAR's `Stable`) |
| `published_text` | The cell as displayed, e.g. `1,234` is `1234`, `np`, `–`, `*7.3`, `Down 4.2%` |
| `value_flag` | A quality marker on a published number, from the value spec's `markers`: `rse_25_to_50` (`*`: relative standard error 25–50%, use with caution), `rse_over_50` (`**`: RSE over 50%, too unreliable for general use), `revised` (`r10,822`), `footnote` (`(b)25.3`). Empty for most values |
| `release_id` | The release the value comes from (`sources.csv`) |
| `n_releases` | How many releases publish this series and period |
| `is_latest` | `TRUE` for exactly one row per series and period: the most recent release's value |
| `differs_from_latest` | `TRUE` where a later release published a different number or, where neither has a number, a different status. Spelling (`np` vs `n.p.`) and quality asterisks don't count |
| `sheet_sha256`, `address` | The source sheet and cell, for tracing any value to the workbook |
| `derived` | Fields not read from the value's own row and column labels, e.g. `state,period` taken from the title |

### `series/<publication_id>.csv`: one row per series

One file per publication (`series/prisoners-australia.csv`), each with only the columns
that publication uses. Until 2026-11-04 this was one `series.csv` for all publications.
With the state crime statistics in, that file would have been 1.4 million rows by about
580 columns, almost all empty. To combine publications, bind the files' rows: the columns
mean the same in every file.

A series is everything that identifies a value except its period. Columns:
- `series_id` and `measure_id`;
- `publication_id`;
- the measure fields the publication uses, from `population`, `scope`, `measure`, `unit`,
  `rate_standardisation`, `estimate_type`, `data_status`, `offence_classification`
  (`population` and `measure` are always there);
- one column per dimension: `state`, `court_level`, `sex`, `age_group`,
  `indigenous_status`, `principal_offence`, …, then the rest alphabetically.

A dimension a series doesn't have is empty. Dimension names come from
`dictionary/dimensions.csv`.

`period_type` is set for periods that aren't a single year: `Pooled 2 years` (`2019–21`
is 2019–20 and 2020–21 together), `Pooled 3 years`, `Range of N years` (a change or
total over a window), `Quarter` (Corrective Services, youth detention) and `Month`
(Corrective Services). These are separate series, so one series has one value per
`reference_date`: the December quarter 2025 and the 2025 annual average end on the same
day.

`measure` says what kind of value it is and `unit` its scale, so a count is `Number` with
`no.` or `'000`, and a percentage is `Proportion` with `%`. In survey RSE tables
(`estimate_type` = `Relative standard error`) the unit is the RSE's own, so the RSE of a
count is `Number` with `%`. `Proportion` doesn't say what it is a percentage of, except in
a few measures that name it (`Proportion of all proceedings`); `orchestrator/ISSUES.md`
I35 lists what's left.

### `measures.csv`: the measure catalogue

One row per publication and combination of measure fields, with the number of series
using it.

### `sources.csv`: one row per sheet

| Column | Meaning |
|---|---|
| `sheet_sha256` | `sha256("<original workbook sha256>/<sheet name>")` |
| `publication_id`, `publication`, `publisher` | |
| `release_id`, `release`, `release_date` | The release. `release_date` is known only for historical releases |
| `xlsx_file`, `sheet` | Workbook in `source-spreadsheets-xlsx/` and exact sheet name |
| `subject`, `title` | The title, and the subject `identify()` matched (`measures/README.md`) |

IDs are the first 16 hex digits of a SHA-256 of the identifying text, so they stay
the same across rebuilds as long as the labels don't change.

### Example (R)

```r
library(dplyr)
obs <- readr::read_csv("integrated/observations.csv")
series <- readr::read_csv("integrated/series/prisoners-australia.csv")

# Latest age-standardised imprisonment rates by state and Indigenous status, all persons
obs |> filter(is_latest) |> inner_join(series, by = "series_id") |>
  filter(measure == "Imprisonment rate", rate_standardisation == "Age standardised",
         is.na(sex) | sex == "Persons") |>
  distinct(period, state, indigenous_status, value, value_status)

# Several publications: bind their files
series <- purrr::map_dfr(c("recorded-crime-victims", "nsw-bocsar-crime-statistics-by-lga"),
  ~ readr::read_csv(sprintf("integrated/series/%s.csv", .x), col_types = readr::cols(.default = "c")))
```

**Totals.** They sit beside their components (e.g. `sex = "Persons"`, `state =
"Australia"`, `principal_offence = "Total"`), so filter on them before summing.

**An empty dimension means the table has no breakdown by it, i.e. the total.** The
same total can come from a by-sex table (`sex = "Persons"`) and from a table without
sex (`sex` empty). These are different series, so both have `is_latest`.

For example, the age-standardised rate has `sex = "Persons"` up to 2021 and no `sex`
from 2022. Filter with `is.na(sex) | sex == "Persons"` and remove duplicates.
`classify()` (next stage) is meant to make implicit totals explicit.

## Specs

**`integration_spec.json`** (`assemble()`):
- `cell_fields`: record fields that locate a cell and are not labels;
- `observation_fields`: fields that vary within a series (`period`, `reference_date`);
- `measure_fields`: fields that describe what is counted, which make up `measure_id`;
- `dimension_order`: column order in the series files;
- `source_fields`: columns of `sources.csv`.

**`value_spec.json`** (`type_values()`): what each publisher's symbols mean. A
workbook's own entries (from its legend, `qa/seeds/seed_value_legends.R`) win over its
publication's, which win over `default`. `value` is set only where a symbol stands for a
number. `markers` are regexes for leading quality markers. They're removed before the
number is read and recorded in `value_flag`, applied in order, so a later (more
specific) marker's flag wins. `rewrites` then read numbers written with words or a
suffix: BOCSAR's significant trends (`Up 4.2%` is `4.2` and `Down 4.2%` is `-4.2`, the
average annual percentage change), clear-up rate changes (`1.9 p.p`) and rate ratios
(`11.1x`).

Many ABS and RoGS workbooks add the asterisks through the number format
(`"*"#,##0.0`), not the cell text. `published_value()` keeps them, as Excel displays
them, so they reach `markers`. Survey estimates and their RSEs are separate series:
`estimate_type` is `Relative standard error` for the RSE, `95% confidence interval` for
the ± interval RoGS publishes beside its survey estimates, and empty or `Estimate` for
the estimate.
- ABS: `np` not published, `na` not available, `..` not applicable, `–` nil or
  rounded to zero.
- AIHW: `n.p.`, `n.a.`, `. .`, `—`.
- NSW BOCSAR, as its workbooks' notes define them: `nc` (also `n.c.`, and `nc**` with a
  footnote marker) not calculated, `1 to 4` not published, `Stable` no significant trend.
- Text that is neither a number nor a listed symbol gets `unrecognised` and is listed
  in the report.

**`reconcile_spec.json`** (`reconcile()`). Releases are ordered by `release_end`, the
latest `reference_date` in their own data. This works the same for historical releases
(which have release dates) and accepted ones (which don't). `release_end_overrides`
corrects a release whose data dates mislead. Within a release, a number is preferred
over a symbol or blank.

## What's not covered yet

`targets::tar_read(integration_gaps)` lists, by publication:
- values that still can't be told apart;
- series without a population or measure;
- value statuses.

Blank cells are included only inside the tables recipes define. Rows or columns that
are blank throughout were usually left out of recipes, labels included, so they are
missing (`orchestrator/ISSUES.md`).
