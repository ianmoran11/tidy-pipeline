library("targets")
library("tarchetypes")
library("crew")

tar_source()
# 6 parallel workers (of 8 cores) that store and load their own results; qs is faster
# than rds for the many small per-sheet objects
tar_option_set(packages = c("readr", "dplyr", "tidyverse", "ggplot2", "openxlsx", "tidyxl", "unpivotr", "cellranger", "rlang", "stringr"),
               controller = crew_controller_local(workers = 6), storage = "worker", retrieval = "worker", format = "qs")


# data_outputs[[1]]$tables %>% map(as_tibble) %>% 
# bind_rows() %>% 
# mutate(tidy_table_list = map(tidy_table_list, as_tibble)) %>% 
# unnest(tidy_table_list) %>%
# mutate(meta_data_list = map(meta_data_list, as_tibble)) %>% 
# unnest(meta_data_list) %>% 
# print(n = Inf)


list(
  tar_target(source_metadata_file, "source_metadata.csv", format = "file"),
  # source_metadata.csv (one row per sheet) is written outside the pipeline by get_source_data.R
  tar_target(source_metadata_df, read_csv(source_metadata_file, col_types = cols(.default = "c", reference_only = "l", sheet_index = "i"),
                                          trim_ws = FALSE, na = c("", "NA"))),
  tar_target(source_metadata_checks, check_source_metadata(source_metadata_df), error = "continue"),
  # Admission: only switched-on releases in sources/dataset_selection.json reach the stages below.
  # selected_sheets reruns every time (it's fast) so new or edited recipe files (recipe_md5) are noticed.
  tar_target(dataset_selection_file, "sources/dataset_selection.json", format = "file"),
  tar_target(dataset_selection, jsonlite::read_json(dataset_selection_file)),
  tar_target(selected_sheets, select_sheets(source_metadata_df, dataset_selection), cue = tar_cue(mode = "always")),
  tar_target(selected_sheets_checks, check_selected_sheets(selected_sheets, dataset_selection, source_metadata_df), error = "continue"),
  tar_target(selection_coverage, dplyr::summarise(dplyr::group_by(selected_sheets, publication_id, release_key), sheets = dplyr::n(),
                                                  with_recipe = sum(has_recipe), .groups = "drop")),
  # Each sheet's branch depends on its row of recipe_sheets, so keep only the fields
  # process_recipe(), check_data() and assemble() read, plus xlsx_sha256 (the workbook's
  # bytes) and recipe_md5. New or changed provenance columns in source_metadata.csv then
  # don't rebuild every branch: a sheet's branches rerun only when one of these fields changes.
  tar_target(recipe_sheets, dplyr::select(dplyr::filter(selected_sheets, has_recipe), dplyr::all_of(c("sheet_sha256", "recipe_path", "recipe_md5",
    "sheets", "xlsx_file", "xlsx_sha256", "reference_only", "active_sheet_sha256", "publication_id", "reference_period",
    "publication", "publisher", "source_release_id", "asset_year", "release", "release_date")))),
  tar_target(data, process_recipe(recipe_sheets, recipe_sheets$recipe_path), pattern = map(recipe_sheets), iteration = "list"),
  tar_target(normalisation_spec_file, "normalisation/normalisation_spec.json", format = "file"),
  tar_target(normalisation_spec, jsonlite::read_json(normalisation_spec_file)),
  tar_target(data_normalised, normalise(data, normalisation_spec), pattern = map(data), iteration = "list"),
  tar_target(harmonisation_spec_file, "harmonisation/harmonisation_spec.json", format = "file"),
  tar_target(harmonisation_spec, jsonlite::read_json(harmonisation_spec_file)),
  tar_target(data_harmonised, harmonise(data_normalised, harmonisation_spec), pattern = map(data_normalised), iteration = "list"),
  tar_target(harmonisation_gaps, harmonisation_report(data_harmonised)),
  tar_target(measure_spec_file, "measures/measure_spec.json", format = "file"),
  tar_target(measure_spec, jsonlite::read_json(measure_spec_file)),
  tar_target(data_identified, identify(data_harmonised, measure_spec), pattern = map(data_harmonised), iteration = "list"),
  # The four per-sheet check functions, run together in one branch per sheet: targets' per-branch
  # bookkeeping, not the checks themselves, dominated the time of four separate check targets
  tar_target(sheet_checks, dplyr::bind_rows(check_data(data, recipe_sheets), check_data_normalised(data_normalised, data, normalisation_spec),
                                            check_data_harmonised(data_harmonised, data_normalised), check_data_identified(data_identified, data_harmonised, measure_spec)),
             pattern = map(data, recipe_sheets, data_normalised, data_harmonised, data_identified), error = "continue"),
  tar_target(integration_spec_file, "integration/integration_spec.json", format = "file"),
  tar_target(integration_spec, jsonlite::read_json(integration_spec_file)),
  tar_target(integrated, assemble(data_identified, recipe_sheets, integration_spec)),
  tar_target(integrated_checks, check_integrated(integrated, data_identified, integration_spec), error = "continue"),
  tar_target(value_spec_file, "integration/value_spec.json", format = "file"),
  tar_target(value_spec, jsonlite::read_json(value_spec_file)),
  tar_target(observations_typed, type_values(integrated$observations, integrated$sources, value_spec)),
  tar_target(observations_typed_checks, check_observations_typed(observations_typed, integrated$observations, value_spec), error = "continue"),
  tar_target(reconcile_spec_file, "integration/reconcile_spec.json", format = "file"),
  tar_target(reconcile_spec, jsonlite::read_json(reconcile_spec_file)),
  tar_target(observations, reconcile(observations_typed, integrated$sources, reconcile_spec)),
  tar_target(observations_checks, check_observations(observations, observations_typed), error = "continue"),
  tar_target(integration_gaps, integration_report(observations, integrated$series, integrated$sources)),
  tar_target(integrated_files, write_integrated(list(observations = observations, series = integrated$series,
                                                     measures = integrated$measures, sources = integrated$sources)), format = "file"),
  tar_target(integrated_files_checks, check_integrated_files(integrated_files, observations, integrated), error = "continue"),
  # Every failed test from the checks above, in one table (warnings included; failed
  # "error" tests also stop their own check target)
  tar_target(check_failures, dplyr::filter(dplyr::bind_rows(source_metadata_checks, selected_sheets_checks, sheet_checks,
    integrated_checks, observations_typed_checks, observations_checks, integrated_files_checks), !passed))
)
