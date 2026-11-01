# Checks for one branch of `data_identified`, against the `data_harmonised` branch it
# came from and the measure spec:
#   - identify() kept every record, cell and value;
#   - it only added fields, never changed existing labels (except those
#     replace_labels allows), and listed what it added in .derived.
# It also reports the known gaps: records without a measure or population, and title
# subjects missing from the spec. Each test returns its failures (none when it passes).
# A failed "error" test stops the branch; "warning" results are only reported. Returns
# one row per test.
check_data_identified <- function(sheet_result, before, measure_spec) {
  spec <- measure_spec; src <- sheet_result$source; sha <- src[["sheet_sha256"]] %||% NA_character_
  records <- unlist(lapply(sheet_result$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  old <- unlist(lapply(before$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  cell <- function(r) paste(r[["row"]], r[["col"]], r[["address"]], r[[".value"]] %||% NA, sep = "|")
  text <- function(v) as.character(v %||% "<none>")[1]

  # Same tables and number of records as the data_harmonised branch it came from
  same_shape_as_input <- function() {
    c(if (length(sheet_result$tables) != length(before$tables)) sprintf("%d tables; data_harmonised had %d", length(sheet_result$tables), length(before$tables)),
      if (length(records) != length(old)) sprintf("%d records; data_harmonised had %d", length(records), length(old)))
  }
  # row, col, address and .value are unchanged, record by record
  cells_unchanged <- function() {
    if (length(records) != length(old)) return("record counts differ")
    a <- vapply(records, cell, ""); b <- vapply(old, cell, "")
    sprintf("%s became %s", b[a != b], a[a != b])
  }
  # Labels already on a record are kept, except those replace_labels lets the subject replace
  existing_labels_kept <- function() {
    if (length(records) != length(old)) return("record counts differ")
    unlist(lapply(seq_along(records), function(i) {
      a <- records[[i]]; b <- old[[i]]
      changed <- Filter(function(f) !identical(a[[f]], b[[f]]) && !(b[[f]] %in% unlist(spec$replace_labels[[f]])), setdiff(names(b), ".derived"))
      sprintf("%s: %s '%s' became '%s'", a[["address"]], changed, vapply(changed, function(f) text(b[[f]]), ""), vapply(changed, function(f) text(a[[f]]), ""))
    }))
  }
  # Fields identify() added are listed in .derived
  added_fields_derived <- function() {
    if (length(records) != length(old)) return("record counts differ")
    unlist(lapply(seq_along(records), function(i) {
      missing <- setdiff(setdiff(names(records[[i]]), names(old[[i]])), strsplit(records[[i]][[".derived"]] %||% "", ",")[[1]])
      sprintf("%s: %s added but not in .derived", records[[i]][["address"]], missing)
    }))
  }
  # Every record says what it measures (known gap: early AIHW recipes without titles)
  measure_present <- function() sprintf("%s has no measure", vapply(Filter(function(r) is.null(r[["measure"]]), records), `[[`, "", "address"))
  # Every record says who is counted (known gap: early AIHW recipes without titles)
  population_present <- function() sprintf("%s has no population", vapply(Filter(function(r) is.null(r[["population"]]), records), `[[`, "", "address"))
  # The title's subject is in the measure spec; new subjects from new batches need an entry
  subject_in_spec <- function() {
    subject <- src[["subject"]] %||% ""
    if (nzchar(subject) && length(records) && is.null(spec$subjects[[src[["publication_id"]]]][[subject]])) sprintf("subject '%s' is not in measures/measure_spec.json", subject)
  }

  severity <- c(same_shape_as_input = "error", cells_unchanged = "error", existing_labels_kept = "error", added_fields_derived = "error",
                measure_present = "warning", population_present = "warning", subject_in_spec = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "data_identified", sheet_sha256 = sha, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("data_identified checks failed for sheet ", sha, ": ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
