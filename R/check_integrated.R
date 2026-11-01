# Checks for `integrated` (assemble() output: observations, series, measures, sources):
#   - the tables have their columns;
#   - there is one observation per record of data_identified, and no cell twice;
#   - IDs are unique and well formed, and every link resolves;
#   - periods and dates are valid, and series and sources are complete.
# It also reports series without a population or measure. Each test returns its
# failures (none when it passes). A failed "error" test stops the target; "warning"
# results are only reported. Returns one row per test.
check_integrated <- function(integrated, data_identified, integration_spec) {
  obs <- integrated$observations; series <- integrated$series; measures <- integrated$measures; sources <- integrated$sources

  # The four tables exist with the columns later stages and analysts read
  tables_have_columns <- function() {
    need <- list(observations = c("series_id", "period", "reference_date", "published_text", "sheet_sha256", "address", "derived"),
                 series = c("series_id", "measure_id", "publication_id", "population", "measure"),
                 measures = c("measure_id", "publication_id", "series"), sources = c(unlist(integration_spec$source_fields), "title"))
    unlist(lapply(names(need), function(t) sprintf("%s lacks column %s", t, setdiff(need[[t]], names(integrated[[t]])))))
  }
  # One observation per record of data_identified
  one_row_per_record <- function() {
    n <- sum(vapply(data_identified, function(s) sum(lengths(lapply(s$tables, `[[`, "tidy_table_list"))), 1L))
    if (n != nrow(obs)) sprintf("%d observations; data_identified has %d records", nrow(obs), n)
  }
  # No cell appears twice
  cells_unique <- function() {
    k <- paste(obs$sheet_sha256, obs$address)
    sprintf("cell %s appears more than once", unique(k[duplicated(k)]))
  }
  # IDs are unique within their own table
  ids_unique <- function() {
    c(sprintf("duplicate series_id %s", unique(series$series_id[duplicated(series$series_id)])),
      sprintf("duplicate measure_id %s", unique(measures$measure_id[duplicated(measures$measure_id)])),
      sprintf("duplicate source sheet %s", unique(sources$sheet_sha256[duplicated(sources$sheet_sha256)])))
  }
  # IDs are 16 hex digits
  ids_well_formed <- function() {
    ids <- unique(c(series$series_id, measures$measure_id))
    sprintf("malformed id '%s'", ids[!grepl("^[0-9a-f]{16}$", ids)])
  }
  # Every link resolves: observation to series and source, series to measure
  links_resolve <- function() {
    c(sprintf("observation series_id %s is not in series", setdiff(obs$series_id, series$series_id)),
      sprintf("observation sheet %s is not in sources", setdiff(obs$sheet_sha256, sources$sheet_sha256)),
      sprintf("series measure_id %s is not in measures", setdiff(series$measure_id, measures$measure_id)))
  }
  # Every observation has a period; reference dates are real dates written YYYY-MM-DD
  periods_and_dates_valid <- function() {
    d <- unique(obs$reference_date[!is.na(obs$reference_date)])
    c(sprintf("%d observations have no period", sum(is.na(obs$period)))[any(is.na(obs$period))],
      sprintf("reference_date '%s'", d[!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d) | is.na(as.Date(d, format = "%Y-%m-%d"))]))
  }
  # Every series has a publication and every source a release
  series_and_sources_complete <- function() {
    c(sprintf("series %s has no publication_id", series$series_id[is.na(series$publication_id)]),
      sprintf("sheet %s has no release_id", sources$sheet_sha256[is.na(sources$release_id)]))
  }
  # Every series says who is counted and what is measured (known gap: early AIHW recipes)
  series_have_population_and_measure <- function() {
    bad <- is.na(series$population) | is.na(series$measure)
    sprintf("%s series %s has no %s", series$publication_id[bad], series$series_id[bad],
            ifelse(is.na(series$population[bad]), "population", "measure"))
  }
  # Column names in series are snake_case, as in dictionary/dimensions.csv
  series_columns_snake_case <- function() sprintf("column '%s'", names(series)[!grepl("^[a-z][a-z0-9_]*$", names(series))])

  severity <- c(tables_have_columns = "error", one_row_per_record = "error", cells_unique = "error", ids_unique = "error",
                ids_well_formed = "error", links_resolve = "error", periods_and_dates_valid = "error", series_and_sources_complete = "error",
                series_have_population_and_measure = "warning", series_columns_snake_case = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "integrated", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("integrated failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
