# Decisions made by the project owner

These are settled. Revisit only if the owner asks.

| # | Decision | Where it lives | Notes |
|---|---|---|---|
| 1 | One recipe per sheet, keyed by `sha256("<original workbook sha256>/<exact sheet name>")` | `get_source_data.R`, `tidy-recipes/` | Uses the *original* file's SHA, so converting XLS to XLSX does not change IDs |
| 2 | Recipe format v0.2 (kind, status, reason, template_from, agent_notes, new_dimensions, caption, validation, generation) | `schema/recipe-v0.2.json` | Status is set only by `submit_recipe` |
| 3 | Agents run headless in parallel, one per workbook, using codemode and dedicated tools | `agents/` | Model `openai-codex/gpt-6.1-sol`, thinking `medium` |
| 4 | Record the agent settings and exact prompt in each recipe (`generation`) | `submit_recipe`, `agents/queue.R manifest` | Pilot recipes were backfilled from logs |
| 5 | Fast mode available for ChatGPT models, off by default | `RECIPE_FAST=1` or `run_agents.sh -f` | Priority tier; Pi does not price it, `queue.R costs` doubles fast runs |
| 6 | **Published values**, not stored values | `R/published_value.R` | Excel-style rounding of the 15-digit decimal. In the pilot review it changed only AIHW values (7,972); a later 200-sheet sample also found ABS cells stored unrounded (e.g. Prisoners `38.5826771653543` → `38.6`) |
| 7 | Agents name dimensions from a human-inspectable dictionary; publisher wording kept in `caption`; new names declared and reviewed | `dictionary/`, skill `references/naming.md` | Validator rejects other names |
| 8 | **Publisher originals are active.** The 73 normalised copies and 3 duplicate archive members are archived for reference only | `source-spreadsheets-xlsx/reference-only/` | The assistant had recommended keeping the copies; the owner chose originals |
| 9 | Normalisation is a separate stage: `data_normalised = normalise(data, normalisation_spec)`, function ≤ 50 lines, spec in JSON | `R/normalise.R`, `normalisation/` | Spec maps raw names/labels to canonical ones |
| 10 | Harmonisation is a separate stage with the same shape | `R/harmonise.R`, `harmonisation/` | |
| 11 | In harmonisation, statistic rows in a category dimension set that category to **Total** | `harmonisation_spec.json` `split` | e.g. `age_group: "Median (years)"` → `age_group: "Total"`, `measure: "Median age"` |
| 12 | Add a standard **`reference_date`** (ISO date) for every period | `reference_dates` in the spec | Financial years end 30 June; plain years are 30 June for Prisoners and child protection |
| 13 | A sheet with no period **falls back to the release reference period** | `fallback_periods` | |
| 14 | Keep the **per-sheet structure** (no flattening into one long table) | | Applies to the per-sheet stages (up to `identify()`). The integrated tables (decisions 16–19) are a separate, later output |
| 15 | Batch order: **ABS first, most recent years first**; EEH skipped for now | `agents/batch-*.txt` | All ABS except EEH is done |
| 16 | Integration stages, each a function plus a JSON spec: `identify` → `assemble` → `type_values` → `reconcile` first; `classify` (codes, hierarchy, totals) next; consistency `check`s later | `R/`, `measures/`, `integration/` | Agreed 2026-11-01 |
| 17 | **Keep every release's value and flag the latest** (`is_latest`), rather than keeping only the latest | `reconcile()` | Revisions stay analysable (`differs_from_latest`) |
| 18 | Integrated output is **CSV** | `integrated/*.csv` | About 460 MB; gitignored |
| 19 | **Blank cells become records with a status** (`value_status = "blank"`) | `blank_value_cells()`, `value_spec.json` | Only blanks inside recipe tables can be recovered so far (ISSUES.md I5) |
| 20 | **One check function per data target**, with each test a separate nested function | `R/check_*.R`, `<target>_checks` targets | Severities (`error` stops the check target, `warning` reports only) chosen by the assistant |
| 21 | **Datasets are admitted per release by switches** in `sources/dataset_selection.json` (handoff from `../tidy-pipeline-to-integrate/`). Unlisted means excluded; nothing is chosen by date | `sources/`, `R/select_sheets.R`, `agents/queue.R` | Switches are the owner's; never reset them from recipe availability |
| 22 | **`source_metadata.csv` is built outside the targets pipeline** (`get_source_data.R`), with minimal code and reliance on specs | `get_source_data.R` | The pinned catalogues are inputs and are never overwritten; `source_metadata.csv` is derived |
| 23 | **All releases of the four ABS justice publications already in the pipeline are switched on** (Criminal Courts, Prisoners, Recorded Crime – Offenders, Federal Defendants: 31 more releases) | `sources/dataset_selection.json` | 2026-11-01. EEH (ABS, not justice) and new ABS justice publications (Corrective Services, Recorded Crime – Victims, Crime Victimisation) were not included |
| 24 | Macro workbooks are converted with Excel set to "Disable all macros without notification" (owner sets it, and resets it afterwards) | `get_source_data.R` (`EXCEL_MACROS_DISABLED=1`) | |
| 25 | New ABS justice releases: pilot 243 sheets, review, then run the rest (1,710) | `agents/batch-abs-new-*.txt` | 2026-11-01 |
| 26 | **Generic label cleaning in normalisation** (whitespace, trailing footnote markers, leading revision `r`), as a `clean` section of the spec | `R/normalise.R`, `normalisation/normalisation_spec.json` | 2026-11-01 |
| 27 | Performance tuning: parallel `crew` workers, `qs` storage, faster extraction, fewer branches (`sheet_checks`, recipe MD5s instead of file targets), vectorised whole-table stages. Outputs unchanged | `_targets.R`, `R/` | 2026-11-01. New dependencies: `crew` (with `mirai`, `nanonext`) and `qs2` |
| 28 | **All releases of the two ABS victims publications are switched on** (Crime Victimisation, Australia: 17; Recorded Crime – Victims: 22); pilot 239 sheets, then the remaining 3,592 | `sources/dataset_selection.json`, `agents/batch-victims-*.txt` | 2026-11-01/02, run overnight on the owner's instruction |
| 29 | Survey quality markers are kept: `published_value()` keeps format asterisks, and `value_flag` records `rse_25_to_50`, `rse_over_50`, `revised`, `footnote` | `R/published_value.R`, `R/type_values.R`, `value_spec.json` `markers` | Chosen by the assistant overnight; follows decision 6 (published values) |
| 30 | 34 dictionary names added for victims dimensions (28 after the pilot, 6 after the full run), each marked "for owner review" | `dictionary/dimensions.csv` | Added so agents in the full run used one name per concept |
| 31 | **Labels are made consistent by a rerunnable seed**: one spelling per label, units out of labels, `period_type`, denominators named in `measure`, `unit_from_measure`, and `differs_from_latest` comparing numbers and statuses instead of text | `qa/seeds/seed_label_consistency.R`, `consistency_rules.R`, `R/identify.R`, `R/reconcile.R` | 2026-11-02. The owner approved the fixes from the audit; the judgement calls within them are in ISSUES.md I35 |
| 32 | **Employee Earnings and Hours is out of the pipeline**: its three switched-on releases are switched off. Its 237 recipes and spec entries stay, so it can be switched back on | `sources/dataset_selection.json` | 2026-11-02, owner's request. `selected_sheets_checks` warns about the recipes left out |
| 33 | **AIHW Child protection 2021–22 to 2024–25 and RoGS Justice 2021–2026 are switched on**, and recipes were written for every sheet of these and the AIHW Youth Justice and RoGS 2020 releases already on (pilot of 4 workbooks, then 48). The 146 early recipes of these publications that failed the validator were rewritten. Spec entries come from `qa/seeds/seed_aihw_rogs_specs.R`; its judgement calls are in ISSUES.md I36 | `sources/dataset_selection.json`, `agents/batch-aihw-rogs-*.txt` | 2026-11-02, owner's request ("group 1"). 59 dictionary names added, each marked for owner review |
| 34 | **13 national justice publications are switched on** ("group 2"), one release each: ABS Corrective Services (June quarter 2026), Personal Safety 2021–22 and its topic releases (partner violence, sexual violence, stalking, childhood abuse), Personal Fraud 2024–25, AIHW youth detention population 2025, young people returning to supervision 2023–24, youth justice and child protection 2022–23, health of people in prisons 2025, and RoGS 2026 child protection and youth justice. Recipes for all 710 sheets (pilot of 6 workbooks, then 29; $7.79). Spec entries come from `qa/seeds/seed_national_specs.R`; its judgement calls are in ISSUES.md I37. AIC Homicide and Deaths in custody are switched off again: R's downloader can't fetch them (I37) | `sources/dataset_selection.json`, `agents/batch-national-*.txt` | 2026-11-03, owner's request. 260 dictionary names added, each marked for owner review |
| 35 | **Per-publication spec entries** where a label or title means something else elsewhere: `publication_split` (harmonisation), `publication_subject_pattern` and `publication_title_flags` (measures), each tried before the shared entries. Plus `combine` in harmonisation, which joins a quarter or month to its year heading | `R/harmonise.R`, `R/identify.R` | 2026-11-03, chosen by the assistant so group 2 couldn't change other publications |

Defaults that were never explicitly decided (candidates to confirm with the owner):

- Recipes keep labels exactly as published, including footnote markers and
  typos; normalisation removes markers.
- Subtotal and total rows are kept and only described in `agent_notes` (I6, I27).
- Releases are ordered by the latest reference date in their own data, then release
  date (`reconcile()`). Within a release, a number beats a symbol for `is_latest`.
- Blank cells get the status `blank`. No meaning such as "not available" is guessed.
- The harmonisation judgements listed in ISSUES.md I28 (e.g. "proven guilty" = "with a
  guilty outcome").
- Symbols that mean nil or rounded to zero get `value = 0`; the status keeps the
  distinction.

Proposed by the assistant and waiting for the owner's answer (2026-11-01):

- Start stage 7, `classify()`: totals, codes and hierarchy (I6, I27).
