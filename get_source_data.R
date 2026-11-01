# Builds source_metadata.csv (one row per sheet) outside the targets pipeline, from the
# release switches and pinned catalogues in sources/dataset_selection.json:
#   1. checks the JSON (schema 2, no duplicate keys, true/false switches) and each
#      catalogue against its SHA-256 pin, and keeps the rows that pass include_rows;
#   2. gives every row its release key: source_release_id without "<publication_id>::",
#      or asset_year (as YYYY-YY for fiscal-year publications);
#   3. prepares the workbooks of switched-on releases that aren't here yet: download,
#      extract the archive member, check source_sha256, then copy XLSX or convert
#      XLS/XLSM with Microsoft Excel (sources/convert_with_excel.applescript);
#   4. writes source_metadata.csv, which has:
#        - every current_pipeline row as it is, archived copies included for lineage;
#        - one row per sheet of each prepared new workbook;
#      and sources/preparation_report.csv, with the status of every switched-on new
#      source file.
# targets admits switched-on releases only (R/select_sheets.R). Run from the project
# root: Rscript get_source_data.R
suppressPackageStartupMessages({ library(dplyr); library(purrr); library(stringr) })
selection_path <- "sources/dataset_selection.json"
xlsx_dir <- "source-spreadsheets-xlsx"; original_dir <- "source-originals"
sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

# 1. The selection and its catalogues --------------------------------------------------
sel <- jsonlite::read_json(selection_path)
duplicates <- function(x) names(x)[duplicated(names(x))]
bad_switches <- unlist(imap(sel$releases, function(r, p) sprintf("%s/%s", p, names(r)[!map_lgl(r, ~ is.logical(.x) && length(.x) == 1 && !is.na(.x))])))
problems <- c(if (!identical(sel[["_schema_version"]], 2L)) "_schema_version is not 2",
              sprintf("duplicate key '%s'", c(duplicates(sel), duplicates(sel$releases), unlist(map(sel$releases, duplicates)))),
              sprintf("switch %s is not true or false", bad_switches))
if (length(problems)) stop(paste(problems, collapse = "\n"), call. = FALSE)
switches <- tibble(publication_id = rep(names(sel$releases), lengths(sel$releases)),
                   release_key = unlist(map(sel$releases, names)), on = unlist(sel$releases))

read_catalogue <- function(name) {
  spec <- sel[["_catalogues"]][[name]]
  path <- file.path(dirname(selection_path), spec$path)
  if (!identical(sha256_file(path), spec$sha256)) stop("catalogue ", name, " (", path, ") does not match its sha256 pin. Review the change, then update the pin deliberately.", call. = FALSE)
  rows <- readr::read_csv(path, col_types = readr::cols(.default = "c"), trim_ws = FALSE, na = c("", "NA"), show_col_types = FALSE)
  eligible <- Reduce(`&`, imap(spec$include_rows %||% list(), ~ rows[[.y]] %in% unlist(.x)), rep(TRUE, nrow(rows)))
  rows %>% mutate(catalogue = name, eligible = eligible)
}
release_key <- function(d) {
  prefix <- paste0(d$publication_id, "::")
  year <- if ("asset_year" %in% names(d)) d$asset_year else NA_character_
  case_when(startsWith(d$source_release_id, prefix) ~ substring(d$source_release_id, nchar(prefix) + 1),
            is.na(d$source_release_id) & d$period_format %in% "fiscal-year" & !is.na(year) ~ sprintf("%s-%02d", year, (as.integer(year) + 1L) %% 100L),
            is.na(d$source_release_id) ~ year)
}
catalogues <- map(set_names(names(sel[["_catalogues"]])), read_catalogue) %>% map(~ mutate(.x, release_key = release_key(.x)))
current <- catalogues$current_pipeline
new <- bind_rows(catalogues[names(catalogues) != "current_pipeline"]) %>% filter(eligible) %>% anti_join(current, by = c("publication_id", "source_sha256")) %>%
  arrange(publication_id, source_sha256) %>% distinct(publication_id, source_sha256, .keep_all = TRUE)
eligible <- bind_rows(filter(current, eligible), new)
unkeyed <- unique(eligible$source_release_id[is.na(eligible$release_key)])
unknown <- anti_join(filter(switches, on), eligible, by = c("publication_id", "release_key"))
if (length(unkeyed) || nrow(unknown)) stop(paste(c(sprintf("no release key for source_release_id %s", unkeyed),
  sprintf("switched-on release %s/%s has no eligible catalogue rows", unknown$publication_id, unknown$release_key)), collapse = "\n"), call. = FALSE)

# 2. Prepare the workbooks of switched-on releases -------------------------------------
new <- new %>% mutate(original_name = str_replace_all(basename(coalesce(archive_member, source_file, download_url)), "[^A-Za-z0-9._-]+", "-"),
                      xlsx_file = sprintf("%s--%s.xlsx", source_sha256, tools::file_path_sans_ext(original_name)))
excel_failures <- 0  # consecutive failed conversions; Excel stops responding while a dialog is open
# Excel asks before opening a workbook with macros, whatever the automation settings,
# and ignores scripts until someone answers. So macro workbooks (an XLS with a VBA
# project, any XLSM) are converted only once Excel is set to "Disable all macros
# without notification" (Excel > Settings > Security) and the run says so:
# EXCEL_MACROS_DISABLED=1 Rscript get_source_data.R
has_macros <- function(path, format) {  # XLS stores the VBA project's name in UTF-16
  format == "xlsm" || length(grepRaw(iconv("_VBA_PROJECT_CUR", to = "UTF-16LE", toRaw = TRUE)[[1]], readBin(path, "raw", file.size(path)), fixed = TRUE)) > 0
}
prepare <- function(row) {
  format <- tolower(row$source_format)
  if (!format %in% c("xlsx", "xls", "xlsm")) return(sprintf("unsupported_format: %s", format))
  out <- file.path(xlsx_dir, row$xlsx_file)
  if (file.exists(out)) return("prepared")
  original <- file.path(original_dir, paste0(row$source_sha256, "--", row$original_name))
  if (!file.exists(original)) {
    download <- tempfile()
    ok <- tryCatch({ utils::download.file(row$download_url, download, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) return("download_failed")
    if (!is.na(row$archive_member)) {
      if (!row$archive_member %in% utils::unzip(download, list = TRUE)$Name) return("archive_member_missing")
      download <- utils::unzip(download, files = row$archive_member, exdir = tempfile(), junkpaths = TRUE)
    }
    if (!identical(sha256_file(download), row$source_sha256)) return("sha256_mismatch: the publisher's bytes differ (a revision?); review before admitting")
    dir.create(original_dir, showWarnings = FALSE); file.copy(download, original)
  }
  if (format != "xlsx" && excel_failures >= 3) return("conversion_skipped: Excel failed 3 times in a row; check it for an open dialog, then rerun")
  if (format != "xlsx" && has_macros(original, format) && Sys.getenv("EXCEL_MACROS_DISABLED") != "1") return("has_macros: set Excel to disable macros without notification, then rerun with EXCEL_MACROS_DISABLED=1")
  if (format == "xlsx") file.copy(original, out) else {
    # Excel converts inside its sandbox container, where it needs no file-access prompt
    box <- file.path(Sys.getenv("HOME"), "Library/Containers/com.microsoft.Excel/Data/tmp/tidy-pipeline-convert")
    dir.create(box, recursive = TRUE, showWarnings = FALSE)
    # short names: Excel can't save to paths longer than 218 characters
    input <- file.path(box, paste0(row$source_sha256, ".", format)); output <- file.path(box, paste0(row$source_sha256, ".xlsx"))
    file.copy(original, input, overwrite = TRUE)
    system2("osascript", c("sources/convert_with_excel.applescript", shQuote(input), shQuote(output)), timeout = 300)
    if (file.exists(output)) file.copy(output, out)
    unlink(c(input, output))
    excel_failures <<- if (file.exists(out)) 0 else excel_failures + 1
  }
  if (file.exists(out)) "prepared" else "conversion_failed"
}
todo <- semi_join(new, filter(switches, on), by = c("publication_id", "release_key"))
# Excel-wide settings each conversion changes and restores; recorded here and restored
# after the run too, in case Excel was blocked by a dialog when a conversion ended
osa <- function(script) suppressWarnings(system2("osascript", c("-e", shQuote(script)), stdout = TRUE, stderr = TRUE))
converting <- any(tolower(todo$source_format) %in% c("xls", "xlsm") & !file.exists(file.path(xlsx_dir, todo$xlsx_file)))
excel_before <- if (converting) osa('tell application "Microsoft Excel" to get {ask to update links, automation security}') else ""
report <- todo %>% mutate(status = map_chr(seq_len(n()), function(i) { message("preparing ", todo$xlsx_file[i]); prepare(todo[i, ]) })) %>%
  select(catalogue, publication_id, release_key, source_sha256, source_format, download_url, archive_member, xlsx_file, status)
readr::write_csv(report, "sources/preparation_report.csv", na = "")
if (grepl("^(true|false), mso", excel_before[1])) {
  s <- strsplit(excel_before[1], ", ")[[1]]
  restored <- osa(sprintf('with timeout of 30 seconds\ntell application "Microsoft Excel"\nset ask to update links to %s\nset automation security to %s\nend tell\nend timeout', s[1], s[2]))
  if (!is.null(attr(restored, "status"))) message("Excel didn't respond. Once its dialog is closed, set it back to: ask to update links ", s[1], ", automation security ", s[2])
}

# 3. One row per sheet ---------------------------------------------------------------
prepared <- filter(new, file.exists(file.path(xlsx_dir, xlsx_file)))
sheets <- if (nrow(prepared)) prepared %>%
  mutate(xlsx_path = file.path(".", xlsx_dir, xlsx_file), sheets = map(xlsx_path, tidyxl::xlsx_sheet_names),
         xlsx_sha256 = map_chr(xlsx_path, sha256_file), reference_only = "FALSE",
         conversion_operation = if_else(tolower(source_format) == "xlsx", "copied_unchanged", "converted")) %>%
  tidyr::unnest(sheets) %>% group_by(xlsx_path) %>% mutate(sheet_index = as.character(row_number())) %>% ungroup() %>%
  mutate(sheet_key = paste0(source_sha256, "/", sheets), sheet_sha256 = as.character(openssl::sha256(sheet_key)))
metadata <- bind_rows(current, sheets) %>% select(-any_of(c("eligible", "original_name"))) %>% arrange(publication_id, source_sha256, as.integer(sheet_index))
readr::write_csv(metadata, "source_metadata.csv", na = "NA")
message(sprintf("source_metadata.csv: %d sheets (%d from prepared new workbooks). Switched-on new source files: %d; %s.",
                nrow(metadata), NROW(sheets), nrow(report), paste(sprintf("%s %d", names(table(report$status)), table(report$status)), collapse = ", ")))
