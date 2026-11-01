# Checks for `integrated_files` (the CSVs write_integrated() wrote), read back as an
# analyst would read them:
#   - each table has its file;
#   - each file has the table's columns and one line per row;
#   - numbers and flags read back unchanged;
#   - missing values are empty fields.
# Each test returns its failures (none when it passes). A failed "error" test stops the
# target; "warning" results are only reported. Returns one row per test.
check_integrated_files <- function(integrated_files, observations, integrated) {
  tables <- list(observations = observations, series = integrated$series, measures = integrated$measures, sources = integrated$sources)
  paths <- stats::setNames(file.path(dirname(integrated_files[1]), paste0(names(tables), ".csv")), names(tables))
  csv <- lapply(paths[file.exists(paths)], data.table::fread, colClasses = "character", na.strings = "", encoding = "UTF-8", strip.white = FALSE)

  # Each table has a file, and the target lists every file
  files_exist <- function() {
    c(sprintf("missing file %s", paths[!file.exists(paths)]),
      sprintf("integrated_files does not list %s", setdiff(paths, integrated_files)))
  }
  # Each file has the table's columns, in order
  columns_match <- function() sprintf("%s.csv columns differ from the table", Filter(function(t) !identical(names(csv[[t]]), names(tables[[t]])), names(csv)))
  # Each file has one line per table row
  row_counts_match <- function() {
    bad <- Filter(function(t) nrow(csv[[t]]) != nrow(tables[[t]]), names(csv))
    sprintf("%s.csv has %d rows; the table has %d", bad, vapply(bad, function(t) nrow(csv[[t]]), 1L), vapply(bad, function(t) nrow(tables[[t]]), 1L))
  }
  # Values, flags and IDs in observations.csv read back unchanged
  observations_round_trip <- function() {
    o <- csv$observations
    value <- as.numeric(o$value)
    bad <- !((is.na(value) & is.na(observations$value)) | abs(value - observations$value) <= 1e-9 * pmax(1, abs(observations$value)))
    c(sprintf("row %d: value %s read back as %s", which(bad %in% TRUE), observations$value[bad %in% TRUE], o$value[bad %in% TRUE]),
      sprintf("%s does not read back unchanged", Filter(function(col) !identical(as.character(observations[[col]]), as.character(o[[col]])),
                                                        c("series_id", "period", "published_text", "is_latest", "sheet_sha256", "address"))))
  }
  # Missing values are written as empty fields, never as the text "NA"
  no_na_text <- function() {
    unlist(lapply(names(csv), function(t) {
      cols <- Filter(function(col) any(csv[[t]][[col]] %in% "NA"), names(csv[[t]]))
      sprintf("%s.csv column %s contains the text 'NA'", t, cols)
    }))
  }

  severity <- c(files_exist = "error", columns_match = "error", row_counts_match = "error", observations_round_trip = "error", no_na_text = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "integrated_files", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("integrated_files failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
