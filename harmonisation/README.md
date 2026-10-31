# Harmonisation spec

`harmonisation_spec.json` drives `harmonise()` (`R/harmonise.R`), which runs on each
sheet after `normalise()`. Its goal: every value's record carries every dimension the
value depends on, one concept per dimension. Edit the JSON directly; `tar_make()` reruns
`data_harmonised` when it changes.

For each record, in order:

1. **Table labels.** Table-level `meta_data` dimensions (for example a `"Males"` block
   label) are copied onto the record. Titles, subtitles, notes and sources are not.
2. **`unstack`.** Old recipes that list several characteristics in one column
   (`characteristic: "Sex"`, `category: "Males"`) become the named dimension
   (`sex: "Males"`).

   ```json
   "unstack": { "characteristic": { "value_from": "category", "names": { "Sex": "sex" } } }
   ```
3. **`split`.** A label that carries several dimensions is replaced by them. Keys are
   the dimension, then the exact label. `null` removes a dimension. Splits may not
   contradict a label already on the record (an error names the sheet and cell),
   except for dimensions listed in `_replace`.

   ```json
   "population": { "Non-Indigenous children": { "indigenous_status": "Non-Indigenous", "population": "Children" } },
   "age_group":  { "Median (years)": { "measure": "Median age", "unit": "years", "age_group": "Total", "_replace": ["measure", "unit"] } },
   "measure":    { "Female": { "sex": "Females", "measure": null } }
   ```
4. **`from_title`.** Dimensions still missing are taken from the table title and
   subtitle. Rules run in order; the first rule for a dimension with exactly one
   distinct match wins. `values` maps the lower-case match to a canonical label,
   `value` gives a fixed label, and `replace` applies regex replacements.

   ```json
   { "dimension": "state", "pattern": "(?<![A-Za-z])(New South Wales|…)(?![A-Za-z])", "values": { "new south wales": "NSW" } }
   ```
   **`fallback_periods`.** A record still without `period` takes the release's
   reference period from `source_metadata.csv`, mapped through this object
   (`"2009-10": "2009–10"`, `"2021-05": "May 2021"`).
5. **`reference_dates`.** `reference_date` (ISO date) is looked up from `period`, first
   in the publication's own object, then in `default`. Financial years end on 30 June,
   months on their last day, ranges on their last period; plain years are 30 June for
   Prisoners and child protection. Periods not listed get no `reference_date`.

Each record's `.derived` lists the dimensions that steps 3–5 added or changed.
`row`, `col`, `address` and `.value` never change.

`targets::tar_read(harmonisation_gaps)` reports what is still missing: records without
`period`, `reference_date` or `measure` by publication, period labels with no date, and
how many records each derived dimension came from.
