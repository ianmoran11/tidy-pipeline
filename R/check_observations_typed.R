# Checks for `observations_typed` (type_values() output), against the observations it
# was given and the value spec:
#   - rows and existing columns are unchanged;
#   - every status is one the spec defines;
#   - published numbers equal their text, blanks are exactly the empty cells, and
#     symbols carry only the value the spec gives them.
# It also reports any text left unrecognised. Each test returns its failures (none
# when it passes). A failed "error" test stops the target; "warning" results are only
# reported. Returns one row per test.
check_observations_typed <- function(observations_typed, observations, value_spec) {
  spec <- value_spec; new <- observations_typed
  text <- stringr::str_squish(new$published_text)
  for (mk in spec$markers) text <- sub(mk[["pattern"]], "", text, perl = TRUE)  # as type_values() reads it
  symbols <- purrr::map_dfr(spec$symbols, function(s) tibble::tibble(status = purrr::map_chr(s, "status"), value = purrr::map_dbl(s, ~ as.numeric(.x[["value"]] %||% NA))))
  where <- function(bad) { bad <- bad %in% TRUE; sprintf("%s %s: '%s' -> %s (%s)", new$sheet_sha256[bad], new$address[bad], text[bad], new$value[bad], new$value_status[bad]) }

  # Rows and the columns type_values() was given are unchanged
  rows_unchanged <- function() {
    if (nrow(new) != nrow(observations)) return(sprintf("%d rows; input had %d", nrow(new), nrow(observations)))
    sprintf("column %s changed", Filter(function(col) !identical(new[[col]], observations[[col]]), names(observations)))
  }
  # Every status is one the spec defines
  statuses_allowed <- function() {
    sprintf("status '%s'", setdiff(unique(new$value_status), c(spec$number_status, spec$blank_status, symbols$status, "unrecognised")))
  }
  # No value text is left unrecognised
  none_unrecognised <- function() sprintf("'%s' is not a number or a known symbol", unique(text[new$value_status == "unrecognised"]))
  # Published numbers equal their text with thousands separators removed
  published_values_parse <- function() {
    p <- new$value_status == spec$number_status
    parsed <- suppressWarnings(as.numeric(gsub(",", "", text)))
    where(p & (is.na(new$value) | is.na(parsed) | new$value != parsed))
  }
  # Blank status exactly where the published cell is empty, and never with a value
  blanks_consistent <- function() {
    blank <- new$value_status == spec$blank_status
    where((is.na(text) | text == "") != blank | (blank & !is.na(new$value)))
  }
  # Symbols carry the value the spec gives their status (0 for nil or rounded to zero), others none
  symbol_values_from_spec <- function() {
    sym <- new$value_status %in% symbols$status
    expected <- symbols$value[match(new$value_status, symbols$status)]
    where(sym & !((is.na(expected) & is.na(new$value)) | (!is.na(expected) & new$value %in% expected)))
  }
  # Values are finite numbers or missing
  values_finite <- function() where(!is.na(new$value) & !is.finite(new$value))
  # Every value flag is one the spec defines, and only numbers carry one
  flags_allowed <- function() {
    c(sprintf("value_flag '%s'", setdiff(unique(na.omit(new$value_flag)), vapply(spec$markers, `[[`, "", "flag"))),
      where(!is.na(new$value_flag) & is.na(new$value)))
  }

  severity <- c(rows_unchanged = "error", statuses_allowed = "error", none_unrecognised = "warning", published_values_parse = "error",
                blanks_consistent = "error", symbol_values_from_spec = "error", values_finite = "error", flags_allowed = "error")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "observations_typed", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("observations_typed failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
