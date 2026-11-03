# Make every record in one sheet's output self-contained, using
# harmonisation/harmonisation_spec.json (see harmonisation/README.md):
#   1. table meta_data labels (e.g. a "Males" block) are added to each record;
#   2. stacked characteristic/category pairs become the named dimension ("unstack");
#   3. a label completed by another is joined to it ("combine": "June quarter" + "2025"),
#      then compound labels are split into several dimensions ("split");
#   4. missing dimensions come from the table title ("from_title", one match only),
#      then from the subtitle (which names the release period, so it must not
#      outvote the title), then period falls back to the release's reference period;
#   5. reference_date is added from period ("reference_dates").
# Dimensions added or changed by steps 3-5 are listed in .derived. row, col, address and
# .value never change; a split that contradicts a label already on the record is an error.
harmonise <- function(sheet_result, harmonisation_spec) {
  spec <- harmonisation_spec; src <- sheet_result$source
  dates <- c(spec$reference_dates[[src[["publication_id"]]]], spec$reference_dates[["default"]])
  # The publication's own splits come first, so a label can mean something else elsewhere
  splits <- spec$split
  for (dim in names(spec$publication_split[[src[["publication_id"]]]])) splits[[dim]] <- c(spec$publication_split[[src[["publication_id"]]]][[dim]], splits[[dim]])
  from_title <- function(title, found = list()) {
    for (rule in spec$from_title) {
      m <- stringr::str_match_all(title, stringr::regex(rule[["pattern"]], ignore_case = TRUE))[[1]][, 2]
      for (r in rule[["replace"]]) m <- gsub(r[[1]], r[[2]], m, perl = TRUE)
      if (!is.null(found[[rule[["dimension"]]]]) || length(unique(tolower(m))) != 1) next
      found[[rule[["dimension"]]]] <- rule[["value"]] %||% rule[["values"]][[tolower(m[1])]] %||% m[1]
    }
    found
  }
  unstack <- function(rec) {
    for (from in in_both(names(spec$unstack), names(rec))) {
      rule <- spec$unstack[[from]]
      to <- rule[["names"]][[rec[[from]]]]
      if (is.null(to) || is.null(rec[[rule[["value_from"]]]])) next
      rec[[to]] <- rec[[rule[["value_from"]]]]; rec[[from]] <- NULL; rec[[rule[["value_from"]]]] <- NULL
    }
    rec
  }
  # A label that needs another to be complete ("Jun Qtr" under a year heading "2025")
  combine <- function(rec) {
    for (from in in_both(names(spec$combine), names(rec))) {
      rule <- spec$combine[[from]]; into <- rule[["into"]]
      if (is.na(rec[[from]]) || is.null(rec[[into]]) || is.na(rec[[into]])) next
      for (r in rule[["when"]]) if (grepl(r[["pattern"]], rec[[into]], perl = TRUE)) {
        rec[[into]] <- paste(rec[[into]], rec[[from]]); rec[[from]] <- NULL
        for (to in names(r[["set"]])) rec[[to]] <- r[["set"]][[to]]
        break
      }
    }
    rec
  }
  split_labels <- function(rec) {
    for (dim in in_both(names(splits), names(rec))) {
      parts <- if (is.na(rec[[dim]])) NULL else splits[[dim]][[rec[[dim]]]]
      for (to in not_in(names(parts), c(dim, "_replace", unlist(parts[["_replace"]])))) {
        if (!is.null(rec[[to]]) && !identical(rec[[to]], parts[[to]])) stop("Splitting ", dim, " '", rec[[dim]], "' at ", src[["sheet_sha256"]], " ", rec[["address"]], " contradicts ", to, " '", rec[[to]], "'")
      }
      for (to in not_in(names(parts), "_replace")) rec[[to]] <- parts[[to]]
    }
    rec
  }
  sheet_title <- unlist(sheet_result$sheet_metata[["table_title"]]); subtitle <- unlist(sheet_result$sheet_metata[["table_subtitle"]])
  sheet_result$tables <- lapply(sheet_result$tables, function(table) {
    meta <- table$meta_data_list
    constants <- from_title(paste(subtitle, collapse = " / "), from_title(paste(c(unlist(meta[["table_title"]]), sheet_title), collapse = " / ")))
    labels <- lapply(meta[setdiff(names(meta), c("table_title", "table_subtitle", "notes", "source"))], paste, collapse = " ")
    table$tidy_table_list <- lapply(table$tidy_table_list, function(rec) {
      rec <- base <- unstack(c(rec, labels[not_in(names(labels), names(rec))]))
      rec <- split_labels(combine(rec))
      for (dim in not_in(names(constants), names(rec))) rec[[dim]] <- constants[[dim]]
      if (is.null(rec[["period"]]) && !is.na(src[["reference_period"]] %||% NA)) rec[["period"]] <- spec$fallback_periods[[src[["reference_period"]]]] %||% src[["reference_period"]]
      if (!is.null(rec[["period"]]) && !is.na(rec[["period"]])) rec[["reference_date"]] <- dates[[rec[["period"]]]]
      rec[[".derived"]] <- paste(names(rec)[vapply(names(rec), function(n) !identical(rec[[n]], base[[n]]), TRUE)], collapse = ",")
      rec
    })
    table
  })
  sheet_result
}
