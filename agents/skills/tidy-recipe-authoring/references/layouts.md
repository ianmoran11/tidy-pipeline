# Recurring layouts

Add new patterns here as they come up. Each pattern names an example recipe in
`../examples/`.

## Common sheet furniture

Most ABS sheets look like this:

| Cells | What | Put it in |
|---|---|---|
| `A1` | Accessibility description of the tab | sheet `meta_data` as `sheet_description` (optional) |
| `A2` | Publisher name | leave out |
| `A3` | Table title, starting `Table N` | sheet `meta_data` `table_title` |
| `A4` | Publication and release | sheet `meta_data` `table_subtitle` |
| row 5–7 | Column headings | headers |
| first column of the heading rows | Caption of the row labels, e.g. `Principal offence(c)` | sheet `meta_data` `stub_heading` |
| below the table | Notes, `np = not published`, footnotes `(a)…` | sheet `meta_data` `notes` (one range) |
| last row | `© Commonwealth of Australia` | leave out |

Cells left out must be outside every table `range`.

## Repeated blocks with a block label

Example: `examples/table-38-sex-blocks-with-spacers.json`.

The same column headings serve several vertical blocks, each introduced by a
label row (`Males`, `Females`, `Persons(i)`):

- One table per block. `range` runs from the block label to its last row
  (the first block's range may include the shared heading rows).
- The block label goes in that table's `meta_data`, named from the dictionary
  (`sex`, `method_of_proceeding`, `indigenous_status`, ...), not in headers.
- Shared column headers (`B6:K6`, `B5,G5`) are repeated in every table.

## Spanning column headings

`Number` over B:F and `Offender rate(b)` over G:K, written only in B5 and G5:
header `measure`, direction `NNW`, cells `"B5,G5"`. Years in row 6 below are
header `period`, direction `N`.

## Blank spacer rows

Rows 12, 17, 21, ... are empty. List populated runs only, in both
`values_range` and the row-label header. Otherwise `run_recipe` reports blank
values and records without labels.

## Hierarchical row labels

`01 Homicide and related offences` followed by indented `011 Murder`: keep
every row in one `W` header (`principal_offence`) with labels as published.
Note in `agent_notes` that parent rows are subtotals. Do not add a second
header for the parent unless the parent label has no values of its own; then
use `WNW` on the parent cells with the dictionary's parent name
(`principal_offence_division`, `method_of_finalisation_group`, ...).

## Stacked sections down the rows

Example layout (Table 37 style): a section caption row (`Sex`, `Age`,
`Indigenous status`) followed by its category rows, all under the same columns:

- One table per section. Name the row header after the section's dimension
  (`sex`, `age_group`, `indigenous_status`) and put the caption text in the
  header's `caption`.
- Start each table's `range` below its caption, and list the caption cells in
  the sheet's `stub_heading` item (one item, cells separated by commas).
- If a second measure block follows (a new caption in column B such as
  `Offenders of FDV as a proportion of all offenders (%)`), start new tables
  for it and put that caption in their `meta_data` as `measure`.

## Cells that differ only by position

`run_recipe` fails when two value cells have exactly the same labels but different
values: the pipeline could not tell them apart. Every value needs a label, from a
header or a table `meta_data` item, that says what it is. A table's `name` is not a
label. `table_subtitle`, `notes`, `source`, `annotations` and `stub_heading` are not
labels either. The patterns below are the usual causes.

## Several titled tables on one sheet

AIHW sheets often stack tables `S126a`, `S126b`, `S126c`, each with its own title row
(`Young people under supervision…`, `…under community-based supervision…`, `…in
detention…`). Make one table per titled block and put its title cell in that table's
`meta_data` as `table_title`. Leave the sheet-level `table_title` out. The pipeline
then reads each table's title, which is what tells the blocks apart.

## Long-format AIHW tables with a Category column

Some AIHW tables are long, with columns such as `Indigenous status`, `Category`, `Sub
Category`, `Data type`, then one column per state:
- every one of these columns is a header (direction `W`), named for its concept;
- `Category` is a dimension even when it is constant over a block (e.g.
  `Investigations outcome` vs `Finalised investigation outcome`). Name it for what it
  distinguishes, from the dictionary or as a declared new dimension;
- `Data type` (`Number`, `Per cent`, `Number per 1,000`) is `measure`.

Never use `table_subtitle` for a label that varies within the sheet.

## Estimates with confidence intervals (RoGS surveys)

Report on Government Services survey tables (police satisfaction, perceptions of
safety) pair each state's estimate with an unlabelled column holding its 95%
confidence interval (`±` percentage points). The notes explain it, e.g. `C182`: `The
95% confidence interval (a reliability estimate) associated with each estimate is
reported…`. Do this:
- one table for the estimate columns and one for the interval columns, sharing the row
  headers;
- in each interval table, add `meta_data` `estimate_type` whose cell is that note (one
  cell; it can stay in the sheet `notes` too). Leave the estimate tables without
  `estimate_type`.

Asterisks on values (`*2.9`) are RSE quality markers. Keep them in the value.
