# tidy-pipeline

An R [`targets`](https://docs.ropensci.org/targets/) pipeline that turns published
Australian justice and crime statistics spreadsheets into one integrated, tidy dataset:
one row per published value, with every dimension needed to interpret it, linked back
to its source workbook and cell.

**The dataset:** download the zipped CSVs from the
[latest release](https://github.com/ianmoran11/tidy-pipeline/releases/latest). It holds
3,989,690 values in 721,701 series from 129 releases of 10 publications by the ABS,
AIHW and Productivity Commission (2001–2025). `integration/README.md` is the data
dictionary.

| File | One row per |
|---|---|
| `observations.csv` | published value: series, period, reference date, value, status (published / not published / not available / blank …), quality flag (e.g. relative standard error 25–50%), release, whether it's the latest release's value, source sheet and cell |
| `series.csv` | series: publication, what is counted (population, measure, unit, estimate type …) and one column per dimension (state, sex, age group, offence, court level …) |
| `measures.csv` | measure: the measure catalogue |
| `sources.csv` | source sheet: publication, release, workbook, sheet, title |

### Data model

```mermaid
erDiagram
    SOURCES ||--o{ OBSERVATIONS : "sheet_sha256"
    SERIES ||--o{ OBSERVATIONS : "series_id"
    MEASURES ||--o{ SERIES : "measure_id"

    OBSERVATIONS {
        string series_id FK
        string period "as published, e.g. 2023–24"
        date reference_date "end of the period"
        float value "the number, rounded as published"
        string value_status "published, blank, not_published, not_available, ..."
        string value_flag "rse_25_to_50, rse_over_50, revised, footnote"
        string published_text "the cell as displayed"
        string release_id "the release that published it"
        int n_releases "releases publishing this series and period"
        bool is_latest "one per series and period"
        bool differs_from_latest "revised in a later release"
        string sheet_sha256 FK
        string address "source cell, e.g. B12"
        string derived "fields not read from the cell's own labels"
    }
    SERIES {
        string series_id PK
        string measure_id FK
        string publication_id
        string population "who is counted"
        string measure
        string unit
        string estimate_type "e.g. Relative standard error"
        string state
        string sex
        string age_group
        string principal_offence "and about 180 more dimension columns"
    }
    MEASURES {
        string measure_id PK
        string publication_id
        string population
        string scope
        string measure
        string unit
        string rate_standardisation
        string estimate_type
        string data_status
        string offence_classification
        int series "number of series"
    }
    SOURCES {
        string sheet_sha256 PK "sha256 of source workbook sha256 / sheet name"
        string publication_id
        string publication
        string publisher
        string release_id
        string release
        date release_date
        string xlsx_file
        string sheet
        string subject "who the title says is counted"
        string title
    }
```

A *series* is everything that identifies a value except its period: the publication,
what is counted (the measure fields, which make up `measure_id`) and one column per
dimension. A dimension a series doesn't have is empty, which means its total.
`release_id` in `observations` names the release; `sources.csv` gives its date and
name.

```r
library(dplyr)
obs <- readr::read_csv("observations.csv")
series <- readr::read_csv("series.csv")
obs |> filter(is_latest) |> inner_join(series, by = "series_id") |>
  filter(publication_id == "prisoners-australia", measure == "Imprisonment rate")
```

## How it works

```mermaid
flowchart TD
    subgraph SRC["Sources: get_source_data.R, outside targets"]
        sel["sources/dataset_selection.json<br/>one switch per release"]
        cat["sources/catalogues/*.csv<br/>source files, pinned by SHA-256"]
        gsd["get_source_data.R<br/>download, check SHA-256, convert XLS with Excel"]
        files[("source-spreadsheets-xlsx/<br/>source-originals/")]
        meta["source_metadata.csv<br/>one row per sheet"]
        sel --> gsd
        cat --> gsd
        gsd --> files
        gsd --> meta
    end

    subgraph REC["Recipes: LLM agents"]
        dict["dictionary/dimensions.csv<br/>dimension names"]
        agents["agents/run_agents.sh<br/>Pi coding agent + recipe validator"]
        recipes["tidy-recipes/*.json<br/>one recipe per sheet"]
        dict --> agents
        agents --> recipes
    end
    files --> agents

    subgraph TAR["targets pipeline: _targets.R"]
        selected["selected_sheets<br/>select_sheets()"]
        subgraph PER["per sheet: one branch each"]
            data["data<br/>process_recipe()"]
            norm["data_normalised<br/>normalise()"]
            harm["data_harmonised<br/>harmonise()"]
            iden["data_identified<br/>identify()"]
        end
        subgraph WHOLE["whole dataset"]
            asm["integrated<br/>assemble()"]
            typ["observations_typed<br/>type_values()"]
            recon["observations<br/>reconcile()"]
        end
        csv[("integrated/*.csv")]
        selected --> data --> norm --> harm --> iden --> asm --> typ --> recon --> csv
    end
    sel --> selected
    meta --> selected
    recipes --> selected
    files --> data

    nspec(["normalisation_spec.json<br/>names, spellings, cleaning"]) -.-> norm
    hspec(["harmonisation_spec.json<br/>splits, title rules, dates"]) -.-> harm
    mspec(["measure_spec.json<br/>title subjects"]) -.-> iden
    ispec(["integration_spec.json<br/>table layout"]) -.-> asm
    vspec(["value_spec.json<br/>symbols, quality markers"]) -.-> typ
    rspec(["reconcile_spec.json<br/>release order"]) -.-> recon
```

Each stage is a short R function driven by a JSON spec. The specs hold the knowledge
about the sources, so adding a publication mostly means adding spec entries, not code.
Every data target also has a check function (`R/check_*.R`, 78 tests); failures are
collected in the `check_failures` target. Switching a release on or off, or editing one
recipe, reruns only the affected branches.

```
sources/dataset_selection.json   release switches (true/false) and pinned source catalogues
get_source_data.R                downloads, checks and converts selected workbooks -> source_metadata.csv
tidy-recipes/*.json              one recipe per sheet: where its values and labels are (written by LLM agents)
_targets.R                       extract -> normalise -> harmonise -> identify -> assemble -> type -> reconcile -> CSV
normalisation/, harmonisation/,  JSON specs that drive each stage: the code is small, the knowledge is in the specs
measures/, integration/
dictionary/dimensions.csv        the dimension names recipes use
R/check_*.R                      one check function per data target (78 tests)
agents/                          the recipe-writing agent harness (Pi coding agent)
orchestrator/                    project handover: state, decisions, known issues, data notes, QA scripts
```

Start with [`orchestrator/README.md`](orchestrator/README.md). Then:
- [`sources/README.md`](sources/README.md) explains adding releases;
- [`integration/README.md`](integration/README.md) describes the output tables;
- [`orchestrator/ISSUES.md`](orchestrator/ISSUES.md) lists known limitations.

### Running it

Requires R with `targets`, `tarchetypes`, `crew`, `qs2`, `tidyverse`, `tidyxl`,
`unpivotr`, `cellranger`, `openxlsx`, `jsonlite`, `data.table` and `openssl`.

```r
targets::tar_make()   # about 1.5 hours from scratch for 9,040 sheets on 6 workers
```

Adding a release: switch it on in `sources/dataset_selection.json`, then run
`Rscript get_source_data.R`. That downloads and checks the files; converting XLS needs
Microsoft Excel on macOS. Then write recipes for the new sheets
(`agents/run_agents.sh`) and run `tar_make()`.

`source-originals/` holds the original downloads (XLS, XLSX, ZIP members) of every
source file prepared by `get_source_data.R`, each matching its SHA-256 pin in
`sources/catalogues/`. The reference SQLite database used for quality checks during
development is not included.

## Licence

- **The project's own work** (code, recipes, specs, dictionary, documentation): MIT
  ([`LICENSE`](LICENSE)). Any use is fine.
- **The publishers' statistics** (the spreadsheets in `source-spreadsheets-xlsx/` and
  the integrated dataset derived from them): Creative Commons Attribution 4.0, which
  allows any use with attribution. See [`DATA-LICENSE.md`](DATA-LICENSE.md).
