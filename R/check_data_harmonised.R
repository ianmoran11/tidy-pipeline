# Checks for one branch of `data_harmonised`, against the `data_normalised` branch it
# came from:
#   - harmonise() kept every record, cell and value;
#   - every record has a period, and reference dates are real ISO dates;
#   - .derived names only fields the record has;
#   - labels are single texts.
# It also reports the known gaps: missing reference dates, leftover characteristic and
# category fields, and non-canonical states. Each test returns its failures (none when
# it passes). A failed "error" test stops the branch; "warning" results are only
# reported. Returns one row per test.
check_data_harmonised <- function(sheet_result, before) {
  sha <- sheet_result$source[["sheet_sha256"]] %||% NA_character_
  records <- unlist(lapply(sheet_result$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  old <- unlist(lapply(before$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  cell <- function(r) paste(r[["row"]], r[["col"]], r[["address"]], r[[".value"]] %||% NA, sep = "|")
  field <- function(f) vapply(records, function(r) as.character(r[[f]] %||% NA)[1], "")
  address <- field("address"); period <- field("period"); reference_date <- field("reference_date")

  # Same sheet, tables and number of records as the data_normalised branch it came from
  same_shape_as_input <- function() {
    c(if (!identical(sheet_result$source, before$source)) "source differs from data_normalised",
      if (length(sheet_result$tables) != length(before$tables)) sprintf("%d tables; data_normalised had %d", length(sheet_result$tables), length(before$tables)),
      if (length(records) != length(old)) sprintf("%d records; data_normalised had %d", length(records), length(old)))
  }
  # row, col, address and .value are unchanged, record by record
  cells_unchanged <- function() {
    if (length(records) != length(old)) return("record counts differ")
    a <- vapply(records, cell, ""); b <- vapply(old, cell, "")
    sprintf("%s became %s", b[a != b], a[a != b])
  }
  # Every record has a period
  periods_present <- function() sprintf("%s has no period", address[is.na(period)])
  # reference_date, where present, is a real date written YYYY-MM-DD
  reference_dates_valid <- function() {
    d <- unique(reference_date[!is.na(reference_date)])
    sprintf("reference_date '%s'", d[!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d) | is.na(as.Date(d, format = "%Y-%m-%d"))])
  }
  # Every period has a reference_date (known gap: the publisher typos "Dec 208" and "2022–22")
  reference_dates_present <- function() sprintf("period '%s' has no reference_date", unique(period[!is.na(period) & is.na(reference_date)]))
  # .derived lists only fields the record has
  derived_fields_exist <- function() {
    unlist(lapply(records, function(r) {
      sprintf("%s: .derived names missing field %s", r[["address"]], not_in(strsplit(r[[".derived"]] %||% "", ",")[[1]], c("", names(r))))
    }))
  }
  # Every label is one piece of text, not a list or several values
  labels_are_single_text <- function() {
    unlist(lapply(records, function(r) {
      l <- r[not_in(names(r), c("row", "col", "address", ".value"))]
      sprintf("%s: %s", r[["address"]], names(l)[!vapply(l, function(v) is.character(v) && length(v) == 1, TRUE)])
    }))
  }
  # No old characteristic/category pairs are left (unstack)
  no_stacked_characteristics <- function() {
    ch <- field("characteristic")
    sprintf("characteristic '%s' is not unstacked", unique(ch[!is.na(ch)]))
  }
  # state labels are the canonical ones (known gap: ACT prisoner variants and others)
  states_are_canonical <- function() {
    s <- unique(field("state"))
    sprintf("state '%s'", setdiff(s[!is.na(s)], c("NSW", "Vic.", "Qld", "SA", "WA", "Tas.", "NT", "ACT", "Australia")))
  }

  severity <- c(same_shape_as_input = "error", cells_unchanged = "error", periods_present = "error", reference_dates_valid = "error",
                reference_dates_present = "warning", derived_fields_exist = "error", labels_are_single_text = "error",
                no_stacked_characteristics = "warning", states_are_canonical = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "data_harmonised", sheet_sha256 = sha, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("data_harmonised checks failed for sheet ", sha, ": ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
