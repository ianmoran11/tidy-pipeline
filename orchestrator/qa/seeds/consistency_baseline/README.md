# Pre-seed specs for `seed_label_consistency.R`

The normalisation, harmonisation, measure and integration specs as they were just before
the label consistency seed first ran (2026-11-02), plus `labels.csv`: every label those
specs produce, as `dim`, `label` and the number of series using it.

`seed_label_consistency.R` starts from these files each time, so rerunning it after
changing `consistency_rules.R` gives the same specs from the same rules. It overwrites
the live specs. Hand edits made to the live specs since then must be repeated here
first, or they are lost.

After a rerun, stage every sheet to check for contradictions (a `split` that contradicts
a label stops the build) and for values that have become indistinguishable, before
running `tar_make()`. `qa/stage_sheets.R` does the first.
