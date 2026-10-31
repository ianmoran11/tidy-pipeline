/skill:tidy-recipe-authoring

Review the recipe `tidy-recipes/{sheet_sha256}.json` (status: {status}).

1. Read the recipe and the sheet with `sheet_grid`.
2. Run `run_recipe` and read the samples and failures.
3. Check that:
   - each header is attached in the right direction and covers exactly the
     label cells for its dimension;
   - block labels are in the right table's meta_data;
   - sampled records match the values and labels shown in the grid;
   - nothing in the table area is left out.

If the recipe is wrong and you can fix it, fix it, then `submit_recipe` with
`agent_notes` describing the fix. Otherwise do not change it.

End with `APPROVE` or `REJECT`, followed by specific cell addresses and reasons.
