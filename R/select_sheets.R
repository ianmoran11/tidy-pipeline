# Admission: the active sheets of switched-on releases in sources/dataset_selection.json
# (the "releases" switches, matched on publication_id and release_key), sorted by
# sheet_sha256. Each comes with its recipe path and whether the recipe exists.
# Switched-off and unlisted releases, and archived reference-only copies, are left out.
# source_metadata.csv itself is written outside the pipeline by get_source_data.R.
select_sheets <- function(source_metadata_df, dataset_selection) {
  releases <- dataset_selection$releases
  switches <- tibble::tibble(publication_id = rep(names(releases), lengths(releases)),
                             release_key = unlist(lapply(releases, names)), on = unlist(releases))
  sheets <- dplyr::semi_join(source_metadata_df[!source_metadata_df$reference_only, ], switches[switches$on %in% TRUE, ],
                             by = c("publication_id", "release_key"))
  sheets <- sheets[order(sheets$sheet_sha256), ]
  dplyr::mutate(sheets, recipe_path = file.path("tidy-recipes", paste0(sheet_sha256, ".json")), has_recipe = file.exists(recipe_path))
}
