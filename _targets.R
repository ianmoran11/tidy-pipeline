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
  tar_files(recipe_files, list.files("./tidy-recipes", pattern = "\\.json$", full.names = T)),
  tar_target(data, process_recipe(source_metadata_df, recipe_files), pattern = map(recipe_files), iteration = "list"),
  tar_target(normalisation_spec_file, "normalisation/normalisation_spec.json", format = "file"),
  tar_target(normalisation_spec, jsonlite::read_json(normalisation_spec_file)),
  tar_target(data_normalised, normalise(data, normalisation_spec), pattern = map(data), iteration = "list"),
  tar_target(harmonisation_spec_file, "harmonisation/harmonisation_spec.json", format = "file"),
  tar_target(harmonisation_spec, jsonlite::read_json(harmonisation_spec_file)),
  tar_target(data_harmonised, harmonise(data_normalised, harmonisation_spec), pattern = map(data_normalised), iteration = "list"),
  tar_target(harmonisation_gaps, harmonisation_report(data_harmonised))
)
