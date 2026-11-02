# Checks for one branch of `data` (process_recipe() output for one sheet). It verifies:
#   - the output has the shape later stages read;
#   - the sheet is active and matches its recipe;
#   - every record is a distinct, correctly addressed cell;
#   - labels are single texts and values are published text.
# Each test returns its failures (none when it passes). A failed "error" test stops the
# branch; "warning" results are only reported. Returns one row per test.
check_data <- function(sheet_result, source_metadata_df) {
  src <- sheet_result$source; sha <- src[["sheet_sha256"]] %||% NA_character_
  recipe_path <- file.path("tidy-recipes", paste0(sha, ".json"))
  recipe <- if (file.exists(recipe_path)) jsonlite::read_json(recipe_path) else list()
  records <- unlist(lapply(sheet_result$tables, `[[`, "tidy_table_list"), recursive = FALSE)
  field <- function(f) vapply(records, function(r) as.character(r[[f]] %||% NA)[1], "")
  cells <- data.frame(row = as.integer(field("row")), col = as.integer(field("col")), address = field("address"), value = field(".value"))
  labels <- lapply(records, function(r) r[not_in(names(r), c("row", "col", "address", ".value"))])

  # The output has the parts later stages read
  has_expected_parts <- function() {
    c(sprintf("missing %s", setdiff(c("sheet_metata", "tables", "source"), names(sheet_result))),
      sprintf("source lacks %s", setdiff(c("sheet_sha256", "publication_id", "reference_period"), names(src))),
      sprintf("table %d lacks tidy_table_list or meta_data_list",
              which(!vapply(sheet_result$tables, function(t) all(c("tidy_table_list", "meta_data_list") %in% names(t)), TRUE))))
  }
  # The sheet is an active sheet in source_metadata.csv, under the same publication
  sheet_is_active <- function() {
    row <- source_metadata_df[source_metadata_df$sheet_sha256 %in% sha, ]
    if (nrow(row) != 1) return(sprintf("sheet %s is not in source_metadata.csv", sha))
    c(if (isTRUE(row$reference_only)) "sheet is an archived reference-only copy",
      if (!identical(row$publication_id, src[["publication_id"]])) sprintf("publication %s, metadata says %s", src[["publication_id"]], row$publication_id))
  }
  # Data recipes give records; other kinds (contents, notes) give no tables
  matches_recipe_kind <- function() {
    if (!length(recipe)) return(sprintf("no recipe %s", recipe_path))
    kind <- recipe[["kind"]] %||% "data"
    if (kind == "data" && !length(records)) "data recipe gave no records"
    else if (kind != "data" && length(sheet_result$tables)) sprintf("%s recipe gave tables", kind)
  }
  # Records match the count the validator recorded when the recipe was submitted. Recipes
  # validated before blank cells became records counted only non-blank ones
  matches_recipe_count <- function() {
    expected <- recipe[["validation"]][["records"]]
    found <- c(sum(!is.na(cells$value)), nrow(cells))
    if (!is.null(expected) && !as.integer(expected) %in% found) sprintf("%d records (%d non-blank); the recipe's validation recorded %d", found[2], found[1], as.integer(expected))
  }
  # Every record has row, col and address, and the address matches row and col
  cells_are_addressed <- function() {
    bad <- is.na(cells$address) | is.na(cells$row) | is.na(cells$col) | paste0(cellranger::num_to_letter(cells$col), cells$row) != cells$address
    sprintf("record at %s (row %s, col %s)", cells$address[bad], cells$row[bad], cells$col[bad])
  }
  # No cell appears twice
  cells_are_unique <- function() sprintf("%s appears more than once", unique(cells$address[duplicated(cells$address)]))
  # Every label is one piece of text, not a list or several values
  labels_are_single_text <- function() {
    unlist(lapply(seq_along(labels), function(i) {
      bad <- names(labels[[i]])[!vapply(labels[[i]], function(v) is.character(v) && length(v) == 1, TRUE)]
      sprintf("%s: %s", cells$address[i], bad)
    }))
  }
  # Every record has at least one label
  records_are_labelled <- function() sprintf("%s has no label", cells$address[vapply(labels, function(l) all(is.na(unlist(l))), TRUE)])
  # Values are published text: never empty and never in scientific notation ("1e+05")
  values_are_published_text <- function() {
    bad <- !is.na(cells$value) & (cells$value == "" | grepl("^-?[0-9.]+e[+-]?[0-9]+$", cells$value))
    sprintf("%s = '%s'", cells$address[bad], cells$value[bad])
  }
  # Sheets with records have a title, which identify() and harmonise() read
  has_title <- function() if (length(records) && !length(unlist(sheet_result$sheet_metata[["table_title"]]))) "no table_title"

  severity <- c(has_expected_parts = "error", sheet_is_active = "error", matches_recipe_kind = "error", matches_recipe_count = "warning",
                cells_are_addressed = "error", cells_are_unique = "error", labels_are_single_text = "error",
                records_are_labelled = "warning", values_are_published_text = "error", has_title = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "data", sheet_sha256 = sha, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("data checks failed for sheet ", sha, ": ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
