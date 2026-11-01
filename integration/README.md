# Integrated dataset

The last stages of the pipeline turn the per-sheet records into four linked tables,
written as CSV to `integrated/` (gitignored; rebuild with `targets::tar_make()`):

```
data_identified ─> integrated           assemble()      integration_spec.json
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
| `series_id` | The series the value belongs to (`series.csv`) |
| `period` | Period as published, e.g. `2023–24`, `May 2023`, `30 June 2014` |
| `reference_date` | ISO date the period ends, e.g. `2024-06-30` |
| `value` | The number, rounded as published. Symbols that mean nil or rounded to zero are `0`; other symbols and blanks are empty |
| `value_status` | `published`, `blank` (empty cell in the published table), `not_published`, `not_available`, `not_applicable`, `nil_or_rounded_to_zero` |
| `published_text` | The cell as displayed, e.g. `1,234` is `1234`, `np`, `–`, `*7.3` |
| `value_flag` | A quality marker on a published number, from the value spec's `markers`: `rse_25_to_50` (`*`: relative standard error 25–50%, use with caution), `rse_over_50` (`**`: RSE over 50%, too unreliable for general use), `revised` (`r10,822`), `footnote` (`(b)25.3`). Empty for most values |
| `release_id` | The release the value comes from (`sources.csv`) |
| `n_releases` | How many releases publish this series and period |
| `is_latest` | `TRUE` for exactly one row per series and period: the most recent release's value |
| `differs_from_latest` | `TRUE` where a later release published a different value (a revision) |
| `sheet_sha256`, `address` | The source sheet and cell, for tracing any value to the workbook |
| `derived` | Fields not read from the value's own row and column labels, e.g. `state,period` taken from the title |

### `series.csv`: one row per series

A series is everything that identifies a value except its period. Columns:
- `series_id` and `measure_id`;
- `publication_id`;
- the measure fields: `population`, `scope`, `measure`, `unit`, `rate_standardisation`,
  `estimate_type`, `data_status`, `offence_classification`;
- one column per dimension: `state`, `court_level`, `sex`, `age_group`,
  `indigenous_status`, `principal_offence`, …, then the rest alphabetically.

A dimension a series doesn't have is empty. Dimension names come from
`dictionary/dimensions.csv`.

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
series <- readr::read_csv("integrated/series.csv")

# Latest age-standardised imprisonment rates by state and Indigenous status, all persons
obs |> filter(is_latest) |> inner_join(series, by = "series_id") |>
  filter(publication_id == "prisoners-australia", measure == "Imprisonment rate",
         rate_standardisation == "Age standardised", is.na(sex) | sex == "Persons") |>
  distinct(period, state, indigenous_status, value, value_status)
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
- `dimension_order`: column order in `series.csv`;
- `source_fields`: columns of `sources.csv`.

**`value_spec.json`** (`type_values()`): what each publisher's symbols mean. A
workbook's own entries (from its legend, `qa/seeds/seed_value_legends.R`) win over its
publication's, which win over `default`. `value` is set only where a symbol stands for a
number. `markers` are regexes for leading quality markers. They're removed before the
number is read and recorded in `value_flag`, applied in order, so a later (more
specific) marker's flag wins.

Many ABS and RoGS workbooks add the asterisks through the number format
(`"*"#,##0.0`), not the cell text. `published_value()` keeps them, as Excel displays
them, so they reach `markers`. Survey estimates and their RSEs are separate series:
`estimate_type` is `Relative standard error` for the RSE, and empty or `Estimate` for
the estimate.
- ABS: `np` not published, `na` not available, `..` not applicable, `–` nil or
  rounded to zero.
- AIHW: `n.p.`, `n.a.`, `. .`, `—`.
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
