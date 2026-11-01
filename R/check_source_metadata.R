# Checks for source_metadata_df (source_metadata.csv): one row per sheet, IDs that
# match the exact sheet names, workbooks on disk, and archived copies that point at an
# active sheet. Each test returns its failures (none when it passes). A failed "error"
# test stops the target; "warning" results are only reported. Returns one row per test.
check_source_metadata <- function(source_metadata_df) {
  m <- source_metadata_df

  # The columns later stages read are present
  has_required_columns <- function() {
    sprintf("missing column %s", setdiff(c("sheet_sha256", "sheet_key", "sheets", "sheet_index", "xlsx_path", "xlsx_file",
      "source_sha256", "publication_id", "reference_only", "active_sheet_sha256", "reference_period"), names(m)))
  }
  # Sheet IDs are present, 64 hex digits and unique
  sheet_ids_unique <- function() {
    c(sprintf("malformed sheet_sha256 '%s'", m$sheet_sha256[!grepl("^[0-9a-f]{64}$", m$sheet_sha256)]),
      sprintf("duplicate sheet_sha256 %s", unique(m$sheet_sha256[duplicated(m$sheet_sha256)])))
  }
  # Each ID is sha256("<source_sha256>/<exact sheet name>"). A mismatch means the sheet
  # name was altered on the way in, e.g. trailing spaces trimmed by read_csv()
  sheet_ids_match_names <- function() {
    ok <- as.character(openssl::sha256(paste0(m$source_sha256, "/", m$sheets))) == m$sheet_sha256
    sprintf("'%s' in %s", m$sheets[!ok %in% TRUE], m$xlsx_file[!ok %in% TRUE])
  }
  # Every workbook is on disk
  workbooks_exist <- function() {
    paths <- unique(m$xlsx_path)
    sprintf("missing workbook %s", paths[!file.exists(paths)])
  }
  # Sheet positions start at 1 and don't repeat within a workbook
  sheet_positions_valid <- function() {
    bad <- is.na(m$sheet_index) | m$sheet_index < 1 | duplicated(paste(m$xlsx_file, m$sheet_index))
    sprintf("%s sheet '%s'", m$xlsx_file[bad], m$sheets[bad])
  }
  # Every sheet belongs to a publication
  publications_present <- function() sprintf("no publication_id: %s", unique(m$xlsx_file[is.na(m$publication_id)]))
  # Archived copies point at an active sheet; active sheets point nowhere
  references_point_to_active <- function() {
    active <- m$sheet_sha256[!m$reference_only]
    c(sprintf("archived sheet %s has no active sheet", m$sheet_sha256[m$reference_only & !m$active_sheet_sha256 %in% active]),
      sprintf("active sheet %s has active_sheet_sha256 set", m$sheet_sha256[!m$reference_only & !is.na(m$active_sheet_sha256)]))
  }

  severity <- c(has_required_columns = "error", sheet_ids_unique = "error", sheet_ids_match_names = "error", workbooks_exist = "error",
                sheet_positions_valid = "error", publications_present = "error", references_point_to_active = "error")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "source_metadata_df", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("source_metadata_df failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
