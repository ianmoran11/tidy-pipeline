# Stage 4: say what each record counts. Two tables in one release often differ only
# in their title ("Defendants finalised" vs "Defendants with a guilty outcome"), so
# the title's subject (the text after "Table N", up to the first comma, or the
# publication's own publication_subject_pattern) is looked up in the spec to set
# population, scope and any other fields it names; title_flags
# match the title and subtitle (e.g. a cube code) to set further fields. A sheet
# without a title of its own uses the one sheet_titles gives it (from the workbook's
# contents sheet), else each table's title. Labels in
# replace_labels (e.g. population "Total") give way to the subject's value. A record
# still without a measure gets one from its unit or the publication's default, and a
# record still without a unit gets one from its measure (unit_from_measure).
# Existing record fields are never overwritten. See measures/README.md.
identify <- function(sheet_result, measure_spec) {
  spec <- measure_spec; pub <- sheet_result$source[["publication_id"]]
  pattern <- spec$publication_subject_pattern[[pub]] %||% spec$subject_pattern
  sheet_title <- unlist(sheet_result$sheet_metata[["table_title"]])
  # A sheet titled only on its workbook's contents sheet (Victoria's CSA tables) has that title in sheet_titles
  if (!length(sheet_title)) sheet_title <- unlist(spec$sheet_titles[[sheet_result$source[["sheet_sha256"]]]])
  # The subject key and the fields a title sets (its subject's entry, then title_flags)
  read_title <- function(title_cells) {
    title <- stringr::str_squish(gsub("\u00a0", " ", paste(title_cells, collapse = " ")))
    subject <- stringr::str_match(title, stringr::regex(pattern, ignore_case = TRUE))[, 2]
    key <- stringr::str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(dplyr::coalesce(subject, ""))))
    found <- spec$subjects[[pub]][[key]] %||% list()
    text <- paste(c(title, unlist(sheet_result$sheet_metata[["table_subtitle"]])), collapse = " / ")
    for (flag in c(spec$publication_title_flags[[pub]], spec$title_flags)) {
      if (stringr::str_detect(text, stringr::regex(flag[["pattern"]], ignore_case = TRUE))) found <- c(found, flag[["set"]][setdiff(names(flag[["set"]]), names(found))])
    }
    list(key = key, found = found)
  }
  sheet <- read_title(sheet_title)
  # A sheet without a title of its own may title each of its tables (AIHW "Table S126a", "S126b", ...)
  read <- lapply(sheet_result$tables, function(table) {
    own <- unlist(table$meta_data_list[["table_title"]])
    if (!length(sheet_title) && length(own)) read_title(own) else sheet
  })
  sheet_result$source$subject <- if (length(read)) read[[1]]$key else sheet$key
  sheet_result$tables <- purrr::map2(sheet_result$tables, read, function(table, title) {
    found <- title$found
    table$tidy_table_list <- purrr::map(table$tidy_table_list, function(rec) {
      for (n in in_both(names(spec$replace_labels), in_both(names(rec), names(found)))) if (rec[[n]] %in% unlist(spec$replace_labels[[n]])) rec[[n]] <- NULL
      added <- not_in(names(found), names(rec))
      rec[added] <- found[added]
      if (is.null(rec[["measure"]])) {
        rec[["measure"]] <- spec$measure_from_unit[[rec[["unit"]] %||% ""]] %||% spec$default_measure[[pub]]
        if (!is.null(rec[["measure"]])) added <- c(added, "measure")
      }
      if (is.null(rec[["unit"]]) && !is.null(spec$unit_from_measure[[rec[["measure"]] %||% ""]])) {
        rec[["unit"]] <- spec$unit_from_measure[[rec[["measure"]]]]
        added <- c(added, "unit")
      }
      if (length(added)) rec[[".derived"]] <- paste(c(not_in(strsplit(rec[[".derived"]] %||% "", ",")[[1]], ""), added), collapse = ",")
      rec
    })
    table
  })
  sheet_result
}
