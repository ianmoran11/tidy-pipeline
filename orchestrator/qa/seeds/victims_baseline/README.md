# Pre-seed specs for `seed_victims_specs.R`

The normalisation, harmonisation and measure specs as they were just before the
victims seed last ran (2026-11-02). Hand edits made after the pilot are included: the
dimension-name mappings for victims variants, state spellings, the "Queeensland" and
"–2007 revised" title rules, `age_basis`, and the case-sensitive subject pattern.

To apply changed seed rules:
1. copy these three files over the live specs;
2. stage the victims sheets with `qa/stage_sheets.R` (rows with the pre-seed specs);
3. run the seed on those rows;
4. stage again to check for contradictions.

Hand edits made to the live specs since then must be repeated here first, or they are
lost.
