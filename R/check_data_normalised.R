# Checks for one branch of `data_normalised`, against the `data` branch it came from
# and the normalisation spec:
#   - normalise() changed only names and labels (same records, same cells and values);
#   - no name or label the spec maps is left unmapped;
#   - labels are single texts.
# Each test returns its failures (none when it passes). A failed "error" test stops the
# branch; "warning" results are only reported. Returns one row per test.
check_data_normalised <- function(sheet_result, before, normalisation_spec) {
  spec <- normalisation_spec; sha <- sheet_result$source[["sheet_sha256"]] %||% NA_character_
  records <- unlist(lapply(sheet_result$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  old <- unlist(lapply(before$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  cell <- function(r) paste(r[["row"]], r[["col"]], r[["address"]], r[[".value"]] %||% NA, sep = "|")
  field_names <- unique(unlist(lapply(records, names)))

  # Same sheet, tables and number of records as the data branch it came from
  same_shape_as_input <- function() {
    c(if (!identical(sheet_result$source, before$source)) "source differs from data",
      if (length(sheet_result$tables) != length(before$tables)) sprintf("%d tables; data had %d", length(sheet_result$tables), length(before$tables)),
      if (length(records) != length(old)) sprintf("%d records; data had %d", length(records), length(old)))
  }
  # row, col, address and .value are unchanged, record by record
  cells_unchanged <- function() {
    if (length(records) != length(old)) return("record counts differ")
    a <- vapply(records, cell, ""); b <- vapply(old, cell, "")
    sprintf("%s became %s", b[a != b], a[a != b])
  }
  # No field still has a name the spec renames
  names_are_canonical <- function() {
    to <- vapply(spec$dimension_names, function(x) x %||% NA_character_, "")
    left <- intersect(field_names, names(to)[to != names(to)])
    sprintf("field '%s' should be '%s'", left, to[left])
  }
  # No label is still one the spec replaces
  labels_are_canonical <- function() {
    unlist(lapply(intersect(names(spec$values), field_names), function(dim) {
      to <- vapply(spec$values[[dim]], function(x) x %||% NA_character_, "")
      found <- unique(vapply(records, function(r) as.character(r[[dim]] %||% NA)[1], ""))
      left <- intersect(found, names(to)[to != names(to)])
      sprintf("%s '%s' should be '%s'", dim, left, to[left])
    }))
  }
  # Every label is one piece of text, not a list or several values
  labels_are_single_text <- function() {
    unlist(lapply(records, function(r) {
      l <- r[not_in(names(r), c("row", "col", "address", ".value"))]
      sprintf("%s: %s", r[["address"]], names(l)[!vapply(l, function(v) is.character(v) && length(v) == 1, TRUE)])
    }))
  }
  # Dimension names are snake_case, as in dictionary/dimensions.csv
  names_are_snake_case <- function() sprintf("field '%s'", setdiff(field_names[!grepl("^[a-z][a-z0-9_]*$", field_names)], ".value"))
  # Labels carry no footnote markers such as "(a)" or "(12)"
  labels_have_no_footnote_markers <- function() {
    l <- unique(unlist(lapply(records, function(r) unlist(r[not_in(names(r), c("row", "col", "address", ".value"))]))))
    sprintf("'%s'", l[grepl("\\((?:[a-z]{1,2}|[0-9]{1,2})\\)\\s*$", l, perl = TRUE)])
  }

  severity <- c(same_shape_as_input = "error", cells_unchanged = "error", names_are_canonical = "error", labels_are_canonical = "error",
                labels_are_single_text = "error", names_are_snake_case = "warning", labels_have_no_footnote_markers = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "data_normalised", sheet_sha256 = sha, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("data_normalised checks failed for sheet ", sha, ": ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
