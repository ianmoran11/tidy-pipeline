# Checks for `selected_sheets` (select_sheets() output), against the release switches
# and the full source_metadata_df:
#   - the switches are valid;
#   - only active sheets of switched-on releases are admitted, unique and sorted;
#   - recipes name the exact sheets.
# It also reports what a switched-on release still lacks: prepared sheets
# (get_source_data.R; see sources/preparation_report.csv) or recipes (partial coverage),
# and recipes that the switches leave out. Each test returns its failures (none when it
# passes). A failed "error" test stops the target; "warning" results are only reported.
# Returns one row per test.
check_selected_sheets <- function(selected_sheets, dataset_selection, source_metadata_df) {
  releases <- dataset_selection$releases
  switches <- tibble::tibble(publication_id = rep(names(releases), lengths(releases)), release_key = unlist(lapply(releases, names)),
                             valid = unlist(lapply(releases, function(r) vapply(r, function(x) is.logical(x) && length(x) == 1 && !is.na(x), TRUE))),
                             on = unlist(lapply(releases, function(r) vapply(r, isTRUE, TRUE))))
  on <- switches[switches$on, ]
  release <- function(d) paste(d$publication_id, d$release_key, sep = "/")

  # Every switch is true or false, and no publication or release is listed twice
  switches_valid <- function() {
    c(sprintf("switch %s is not true or false", release(switches)[!switches$valid]),
      sprintf("%s is listed more than once", unique(c(names(releases)[duplicated(names(releases))], release(switches)[duplicated(release(switches))]))))
  }
  # Only switched-on releases are admitted
  only_switched_on_releases <- function() sprintf("%s is admitted but not switched on", unique(setdiff(release(selected_sheets), release(on))))
  # No archived reference-only copy is admitted
  no_reference_copies <- function() sprintf("sheet %s is a reference-only copy", selected_sheets$sheet_sha256[selected_sheets$reference_only %in% TRUE])
  # Sheets are unique and sorted by sheet_sha256, so branches don't depend on row order
  sheets_unique_and_sorted <- function() {
    c(sprintf("sheet %s is admitted twice", unique(selected_sheets$sheet_sha256[duplicated(selected_sheets$sheet_sha256)])),
      if (is.unsorted(selected_sheets$sheet_sha256)) "sheets are not sorted by sheet_sha256")
  }
  # Each recipe names the exact sheet (spaces included) of its sheet_sha256
  recipes_match_sheets <- function() {
    s <- selected_sheets[selected_sheets$has_recipe, ]
    named <- vapply(s$recipe_path, function(p) as.character(jsonlite::read_json(p)[["sheet"]] %||% NA)[1], "")
    bad <- is.na(named) | named != s$sheets
    sprintf("%s names sheet '%s', not '%s'", s$recipe_path[bad], named[bad], s$sheets[bad])
  }
  # Every switched-on release has prepared sheets (run get_source_data.R; see sources/preparation_report.csv)
  switched_on_releases_prepared <- function() {
    prepared <- release(source_metadata_df[!source_metadata_df$reference_only, ])
    sprintf("%s is switched on but has no prepared sheets", setdiff(release(on), prepared))
  }
  # Every admitted sheet has a recipe (known: releases with partial coverage)
  selected_sheets_have_recipes <- function() {
    d <- dplyr::summarise(dplyr::group_by(selected_sheets, publication_id, release_key), sheets = dplyr::n(), missing = sum(!has_recipe), .groups = "drop")
    d <- d[d$missing > 0, ]
    sprintf("%s: %d of %d sheets have no recipe", release(d), d$missing, d$sheets)
  }
  # Recipes the switches leave out (their releases are switched off or unlisted)
  recipes_outside_selection <- function() {
    ids <- sub("\\.json$", "", list.files("tidy-recipes", pattern = "^[0-9a-f]{64}\\.json$"))
    sprintf("recipe %s is not admitted", setdiff(ids, selected_sheets$sheet_sha256))
  }

  severity <- c(switches_valid = "error", only_switched_on_releases = "error", no_reference_copies = "error", sheets_unique_and_sorted = "error",
                recipes_match_sheets = "error", switched_on_releases_prepared = "warning", selected_sheets_have_recipes = "warning",
                recipes_outside_selection = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "selected_sheets", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("selected_sheets failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
