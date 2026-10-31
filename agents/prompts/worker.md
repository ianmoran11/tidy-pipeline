/skill:tidy-recipe-authoring

Create tidy recipes for workbook `{xlsx_file}`.

- Publication: {publication} ({publisher})
- Release or year: {period}
- Sheets needing a recipe: {n_todo} of {n_sheets}

| sheet | sheet_sha256 | current recipe |
|---|---|---|
{sheet_table}

Related workbooks:
{related}

Work through every sheet listed above using the skill's workflow. Use
`codemode` scripts to call the recipe tools, and batch the work: for example,
list the workbook and check templates for all sheets in one script, then read
grids and test recipes a few sheets at a time. Keep script output short.

Name dimensions from `dictionary/dimensions.csv` (see the skill's
`references/naming.md`); declare any name it lacks in `new_dimensions`.

Write each recipe to `tidy-recipes/<sheet_sha256>.json` and finish every sheet
with `submit_recipe`. You may only write recipe files for this workbook.

End with one line per sheet: `sheet | kind | status | records | remaining failures`.
