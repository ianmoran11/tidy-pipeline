# Naming dimensions

Every header and every table `meta_data` item names a dimension. Take names from
`dictionary/dimensions.csv` in the project root so the same concept has the same
name in every recipe. Read it before naming anything. `run_recipe` and
`submit_recipe` reject names that are not in it.

## Choose a name

1. Find the `dimension` row whose `description` fits the labels, whatever the
   publisher calls it. `aliases` and `example_labels` help.
   - "State/territory", "Jurisdiction" → `state`
   - "Year", "Financial year" → `period`
   - "Age group (years)", "Age" → `age_group`
   - Block labels "Indigenous children" / "Non-Indigenous children" → `indigenous_status`
   - NUMBER / PROPORTION (%) block headings → `measure`
2. Keep the publisher's caption for the dimension in `caption`, exactly as
   printed, including footnote markers. Leave `caption` out when the sheet has no
   caption for it.

   ```json
   { "name": "principal_offence", "caption": "Principal offence(c)", "direction": "W", "cells": "A8:A28" }
   ```
3. Never use a name with status `avoid` (category, characteristic, section,
   group, component, outcome, duration, statistic, ...). Its `notes` say what to
   use.

## When nothing fits

Make a new name and declare it in the recipe's `new_dimensions`:

```json
"new_dimensions": [
  { "name": "third_party_order_status",
    "description": "Whether a child in out-of-home care received a third-party parental responsibility order in the year",
    "example_labels": ["Received a third-party order in 2020–21", "Did not receive a third-party order in 2020–21"] }
]
```

- snake_case, singular, specific to the concept: `third_party_order_status`, not `status`.
- The description says what the labels are, in the publication's terms.
- Do not declare a new name for a concept the dictionary already has under
  other wording. A person reviews new names after the run.

## Common cases

- **Stacked sections.** When one column lists several characteristics under
  captions (Sex / Age / Principal offence), make one table per section and name
  the row header after the section: `sex`, `age_group`, `principal_offence`.
  Put the section caption in `caption`. Do not use `characteristic` with
  `category`.
- **Measures.** `measure` is what is counted or calculated (Number, Rate,
  Proportion (%), Median). `unit` is a separate units column or row. Estimate
  vs standard error is `estimate_type`.
- **Hierarchies.** A parent heading above its child rows gets its own dimension
  when the dictionary has one (`principal_offence_division`,
  `method_of_finalisation_group`, `principal_sentence_group`). Otherwise keep
  parents and children in one dimension and describe the hierarchy in
  `agent_notes`.
- **Report on Government Services outlines.** Map each level to a concept
  (`indicator`, `service`, `measure`, `unit`, `indigenous_status`, ...), not to
  its position (`section`, `group`, `subgroup`).
- **Lengths of time** are not `period`: use `case_duration`, `time_in_care`,
  `time_in_placement`, `time_on_order` or `supervision_duration`.

## meta_data names

Sheet-level `meta_data` uses the `sheet_metadata` rows: `table_title`,
`table_number`, `table_subtitle`, `sheet_description`, `stub_heading`, `notes`,
`source`, `release`, `annotations`, `errata`. Use one item per name and list
several cells with commas (`"A3,A33,A60"`), not numbered names
(`stub_heading_2`).

A table's `meta_data` holds dimensions that apply to every value in the table,
named like headers. It may also use `table_title`, `table_subtitle`, `notes` and
`source` for sheets with several titled tables.
