# Stage 4: say what each record counts. Two tables in one release often differ only
# in their title ("Defendants finalised" vs "Defendants with a guilty outcome"), so
# the title's subject (the text after "Table N", up to the first comma) is looked up
# in the spec to set population, scope and any other fields it names; title_flags
# match the title and subtitle (e.g. a cube code) to set further fields. Labels in
# replace_labels (e.g. population "Total") give way to the subject's value. A record
# still without a measure gets one from its unit or the publication's default.
# Existing record fields are never overwritten. See measures/README.md.
identify <- function(sheet_result, measure_spec) {
  spec <- measure_spec; pub <- sheet_result$source[["publication_id"]]
  title <- stringr::str_squish(gsub("\u00a0", " ", paste(unlist(sheet_result$sheet_metata[["table_title"]]), collapse = " ")))
  subject <- stringr::str_match(title, stringr::regex(spec$subject_pattern, ignore_case = TRUE))[, 2]
  key <- stringr::str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(dplyr::coalesce(subject, ""))))
  found <- spec$subjects[[pub]][[key]] %||% list()
  text <- paste(c(title, unlist(sheet_result$sheet_metata[["table_subtitle"]])), collapse = " / ")
  for (flag in spec$title_flags) {
    if (stringr::str_detect(text, stringr::regex(flag[["pattern"]], ignore_case = TRUE))) found <- c(found, flag[["set"]][setdiff(names(flag[["set"]]), names(found))])
  }
  sheet_result$source$subject <- key
  sheet_result$tables <- purrr::map(sheet_result$tables, function(table) {
    table$tidy_table_list <- purrr::map(table$tidy_table_list, function(rec) {
      for (n in intersect(names(spec$replace_labels), intersect(names(rec), names(found)))) if (rec[[n]] %in% unlist(spec$replace_labels[[n]])) rec[[n]] <- NULL
      added <- setdiff(names(found), names(rec))
      rec[added] <- found[added]
      if (is.null(rec[["measure"]])) {
        rec[["measure"]] <- spec$measure_from_unit[[rec[["unit"]] %||% ""]] %||% spec$default_measure[[pub]]
        if (!is.null(rec[["measure"]])) added <- c(added, "measure")
      }
      if (length(added)) rec[[".derived"]] <- paste(c(setdiff(strsplit(rec[[".derived"]] %||% "", ",")[[1]], ""), added), collapse = ",")
      rec
    })
    table
  })
  sheet_result
}
