library("targets")
library("tarchetypes")

tar_source()
tar_option_set(packages = c("readr", "dplyr", "tidyverse", "ggplot2", "openxlsx", "tidyxl", "unpivotr", "cellranger", "rlang", "stringr"))


# data_outputs[[1]]$tables %>% map(as_tibble) %>% 
# bind_rows() %>% 
# mutate(tidy_table_list = map(tidy_table_list, as_tibble)) %>% 
# unnest(tidy_table_list) %>%
# mutate(meta_data_list = map(meta_data_list, as_tibble)) %>% 
# unnest(meta_data_list) %>% 
# print(n = Inf)


list(
  tar_target(source_metadata_file, "source_metadata.csv", format = "file"),
  tar_target(source_metadata_df, read_csv(source_metadata_file, trim_ws = FALSE)),
  tar_target(source_metadata_checks, check_source_metadata(source_metadata_df), error = "continue"),
  tar_files(recipe_files, list.files("./tidy-recipes", pattern = "\\.json$", full.names = T)),
  tar_target(data, process_recipe(source_metadata_df, recipe_files), pattern = map(recipe_files), iteration = "list"),
  tar_target(data_checks, check_data(data, source_metadata_df), pattern = map(data), error = "continue"),
  tar_target(normalisation_spec_file, "normalisation/normalisation_spec.json", format = "file"),
  tar_target(normalisation_spec, jsonlite::read_json(normalisation_spec_file)),
  tar_target(data_normalised, normalise(data, normalisation_spec), pattern = map(data), iteration = "list"),
  tar_target(data_normalised_checks, check_data_normalised(data_normalised, data, normalisation_spec), pattern = map(data_normalised, data), error = "continue"),
  tar_target(harmonisation_spec_file, "harmonisation/harmonisation_spec.json", format = "file"),
  tar_target(harmonisation_spec, jsonlite::read_json(harmonisation_spec_file)),
  tar_target(data_harmonised, harmonise(data_normalised, harmonisation_spec), pattern = map(data_normalised), iteration = "list"),
  tar_target(data_harmonised_checks, check_data_harmonised(data_harmonised, data_normalised), pattern = map(data_harmonised, data_normalised), error = "continue"),
  tar_target(harmonisation_gaps, harmonisation_report(data_harmonised)),
  tar_target(measure_spec_file, "measures/measure_spec.json", format = "file"),
  tar_target(measure_spec, jsonlite::read_json(measure_spec_file)),
  tar_target(data_identified, identify(data_harmonised, measure_spec), pattern = map(data_harmonised), iteration = "list"),
  tar_target(data_identified_checks, check_data_identified(data_identified, data_harmonised, measure_spec), pattern = map(data_identified, data_harmonised), error = "continue"),
  tar_target(integration_spec_file, "integration/integration_spec.json", format = "file"),
  tar_target(integration_spec, jsonlite::read_json(integration_spec_file)),
  tar_target(integrated, assemble(data_identified, source_metadata_df, integration_spec)),
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
  tar_target(check_failures, dplyr::filter(dplyr::bind_rows(source_metadata_checks, data_checks, data_normalised_checks, data_harmonised_checks,
    data_identified_checks, integrated_checks, observations_typed_checks, observations_checks, integrated_files_checks), !passed))
)
