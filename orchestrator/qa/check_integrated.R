# Reads integrated/*.csv as an analyst would and checks the links, uniqueness and
# is_latest; then runs the README example. Run after tar_make().
suppressMessages({library(dplyr)})
t0 <- Sys.time()
obs <- readr::read_csv("integrated/observations.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c", value = "d", n_releases = "i", is_latest = "l", differs_from_latest = "l"))
series_files <- list.files("integrated/series", "\\.csv$", full.names = TRUE)  # one per publication
series_by_pub <- lapply(series_files, readr::read_csv, show_col_types = FALSE, col_types = readr::cols(.default = "c"))
series <- bind_rows(lapply(series_by_pub, function(s) s[c("series_id", "measure_id", "publication_id", "population", "measure")]))
sources <- readr::read_csv("integrated/sources.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
measures <- readr::read_csv("integrated/measures.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
cat("read in", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "s | observations", nrow(obs), "x", ncol(obs), "| series", nrow(series), "in", length(series_files),
    "files, up to", max(vapply(series_by_pub, ncol, 1L)), "columns | measures", nrow(measures), "| sources", nrow(sources), "\n")
cat("observations columns:", paste(names(obs), collapse = ", "), "\n")
cat("every series_id in series/:", all(obs$series_id %in% series$series_id), "| every sheet in sources.csv:", all(obs$sheet_sha256 %in% sources$sheet_sha256), "| every measure_id in measures.csv:", all(series$measure_id %in% measures$measure_id), "\n")
cat("duplicate series_id:", sum(duplicated(series$series_id)), "| duplicate cells:", sum(duplicated(paste(obs$sheet_sha256, obs$address))), "\n")
l <- obs %>% count(series_id, period, wt = is_latest)
cat("series x period:", nrow(l), "| with exactly one is_latest:", sum(l$n == 1), "\n")
cat("published rows with a value:", sum(obs$value_status == "published" & !is.na(obs$value)), "of", sum(obs$value_status == "published"), "| no period:", sum(is.na(obs$period)), "| no reference_date:", sum(is.na(obs$reference_date)), "\n")
cat("\nREADME example:\n")
prisoners <- readr::read_csv("integrated/series/prisoners-australia.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
print(obs |> filter(is_latest) |> inner_join(prisoners, by = "series_id") |>
  filter(measure == "Imprisonment rate", rate_standardisation == "Age standardised", sex == "Persons") |>
  select(period, state, indigenous_status, value, value_status) |> arrange(desc(period), state) |> head(8))
cat("\nseries columns with any value:", length(unique(unlist(lapply(series_by_pub, function(s) names(s)[colSums(!is.na(s)) > 0])))), "\n")
