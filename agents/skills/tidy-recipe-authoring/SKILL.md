---
name: tidy-recipe-authoring
description: Write, test, and submit JSON tidy recipes (tidy-recipes/<sheet_sha256>.json) that turn spreadsheet sheets into tidy records. Use when creating, fixing, or reviewing recipes in this project.
---

# Writing tidy recipes

A recipe describes one sheet. It lives at `tidy-recipes/<sheet_sha256>.json`
and follows `references/recipe-format.md`. Before writing your first recipe,
read that file, `references/layouts.md`, `references/naming.md`, and the
dimension dictionary `dictionary/dimensions.csv` in the project root.

## Tools

Call these from `codemode` scripts as `tools.<name>({...})`. Each returns a
JSON object.

| Tool | Use |
|---|---|
| `list_workbook_sheets({xlsx_file})` | Plan: sheets, sha256s, sizes, headings, existing recipes |
| `sheet_grid({sheet_sha256, range?})` | Read the sheet. Page with `range` when `truncated` is true |
| `find_template_recipes({sheet_sha256})` | Earlier recipes with a similar layout |
| `validate_recipe({path})` | Format checks only |
| `run_recipe({path})` | Format checks + pipeline run + coverage. `passed` tells you if it will validate |
| `submit_recipe({path, agent_notes?})` | Final step. Sets status `validated` or `needs_review` |

Write recipe files with the `write` tool. You cannot run shell commands.

## Workflow for each sheet

1. **Template.** Call `find_template_recipes`. If a template has
   `label_similarity` ≥ 0.6, read it and start from it: copy its structure,
   set the new `sheet_sha256`, `sheet`, and `template_from`, then fix every
   address against `sheet_grid`. Years add columns and rows shift between
   releases, so never reuse an address without checking it. Do not copy the
   template's `status`, `validation`, or `generation` fields. Older templates
   may use names that are not in the dictionary; rename them.
2. **Classify.** Decide `kind` from the grid:
   - `data`: the sheet has a statistical table.
   - `contents`, `notes`: no data table. Give a one-line `reason`.
   - `empty`: no meaningful cells.
   - `unsupported`: a data table the format cannot express. Explain why in
     `reason`; it will go to human review.
3. **Encode.** One table per block of values sharing the same headers.
   Follow `references/layouts.md`. Name every header and table `meta_data`
   item from the dictionary, following `references/naming.md`.
4. **Test.** `run_recipe`. Fix every failure. Read the `samples`: each record
   must have the right labels for its value.
5. **Submit.** `submit_recipe`, with `agent_notes` for anything a reviewer
   should know.

Test several sheets in one script with `Promise.allSettled`, and print only
short summaries (sheet, passed, failures) so your context stays small.

## Rules

- Use only addresses shown by `sheet_grid`. Never guess a range.
- `values_range` and row-header ranges must skip blank spacer rows/columns:
  list populated runs, e.g. `"B8:K11,B13:K16,B18:K20"`.
- Every non-blank cell inside a table's `range` must be a value, a header,
  or a meta_data cell. Column captions above row labels go in sheet
  `meta_data` as `stub_heading`.
- Keep labels exactly as published, including footnote markers like `(b)`
  and leading spaces. Do not clean or rename values.
- Text in value positions (`np`, `..`, `–`, `n.a.`) stays as a value.
- Do not drop subtotal or total rows. Record label hierarchies (indents,
  divisions vs subdivisions) and subtotals in `agent_notes`.
- Names of headers and `meta_data` items come from `dictionary/dimensions.csv`.
  Put the publisher's caption for a dimension in the header's `caption`. If no
  dictionary name fits, declare a specific new name in `new_dimensions`; never
  use names with status `avoid`.
- If `run_recipe` still fails after 3 serious attempts on a sheet, submit it
  anyway (it becomes `needs_review`) and explain in `agent_notes`.
- Never write `status` yourself other than `"draft"`; `submit_recipe` sets it.

## Done

Every sheet in your workbook has a submitted recipe. Finish with one line per
sheet: `sheet | kind | status | records | remaining failures`.
