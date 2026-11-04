# Stage 5: turn the per-sheet records into linked tables for analysis.
#   observations  one row per published value (cell), linked to a series
#   series        one table per publication: one row per publication + measure fields +
#                 dimension values, with only the publication's own columns
#   measures      one row per publication + measure fields (the measure catalogue)
#   sources       one row per sheet: publication, release, workbook, sheet, title
# A series is everything that identifies a value except its period. IDs are the
# first 16 hex digits of a SHA-256 of the identifying text, so they are stable
# across rebuilds. See integration/README.md.
#
# assemble_sheet() runs once per sheet (target `assembled`) and turns its records into plain
# columns; assemble() binds them. Every sheet's records at once took 22 GB of memory, their
# columns a few. One series table for all publications would be 2.3 million rows by 588
# columns (11 GB), almost all empty; one per publication is 23 times smaller.
assemble_sheet <- function(s, integration_spec) {
  spec <- integration_spec; skip <- unlist(c(spec$cell_fields, spec$observation_fields))
  recs <- unlist(purrr::map(s$tables, "tidy_table_list"), recursive = FALSE)
  if (!length(recs)) return(NULL)
  d <- unclass(data.table::rbindlist(recs, fill = TRUE))  # one element per field, one value per record
  dims <- sort(setdiff(names(d), skip))
  # "name=value|..." over the record's own (non-missing) fields, in name order
  key <- do.call(paste0, lapply(dims, function(n) { x <- paste0("|", n, "=", d[[n]]); x[is.na(d[[n]])] <- ""; x }))
  key <- paste0("publication_id=", s$source$publication_id, key)
  field <- function(f) as.character(d[[f]] %||% rep(NA_character_, length(key)))
  first <- !duplicated(key)
  # Plain lists, which rbindlist() reads directly: a data frame per sheet is slow
  list(observations = list(series_key = key, period = field("period"), reference_date = field("reference_date"),
                           published_text = field(".value"), sheet_sha256 = s$source$sheet_sha256, address = field("address"), derived = field(".derived")),
       series = c(list(series_key = key[first], publication_id = s$source$publication_id), lapply(d[dims], `[`, first)),
       title = list(sheet_sha256 = s$source$sheet_sha256, subject = s$source$subject %||% NA_character_,
                    title = paste(unlist(s$sheet_metata[["table_title"]]), collapse = " ")),
       records = sum(lengths(lapply(s$tables, `[[`, "tidy_table_list"))))  # counted as check_integrated() did from data_identified
}

assemble <- function(assembled, source_metadata_df, integration_spec) {
  spec <- integration_spec
  hash <- function(x) substr(as.character(openssl::sha256(x)), 1, 16)
  bind <- function(x, ...) tibble::as_tibble(data.table::setDF(data.table::rbindlist(x, ...)))  # setDF() avoids copying the table
  parts <- purrr::compact(assembled)
  observations <- bind(purrr::map(parts, "observations"))
  # A series' row comes from the first sheet that has it
  keys <- purrr::map(parts, ~ .x$series$series_key)
  first <- split(!duplicated(unlist(keys, use.names = FALSE)), factor(rep(seq_along(parts), lengths(keys)), seq_along(parts)))
  measure_fields <- intersect(unlist(spec$measure_fields), unique(unlist(purrr::map(parts, ~ names(.x$series)))))
  publication <- purrr::map_chr(parts, ~ .x$series$publication_id)
  series <- lapply(split(seq_along(parts), publication), function(ix) {
    s <- bind(lapply(ix, function(i) lapply(parts[[i]]$series, function(col) rep_len(col, length(first[[i]]))[first[[i]]])), fill = TRUE)
    field <- function(f) s[[f]] %||% rep(NA_character_, nrow(s))  # a measure field this publication doesn't use is NA, as in the measure catalogue
    s$measure_id <- hash(do.call(paste, c(list("publication_id", s$publication_id), lapply(measure_fields, field), sep = "|")))
    s$series_id <- hash(s$series_key)
    dims <- setdiff(names(s), c("series_key", "series_id", "measure_id", "publication_id", measure_fields))
    dims <- c(intersect(unlist(spec$dimension_order), dims), sort(setdiff(dims, unlist(spec$dimension_order))))
    for (f in c("population", "measure")) s[[f]] <- field(f)
    # Only the publication's own columns: those with a value, and always who is counted and what is measured
    keep <- function(f) f %in% c("series_id", "measure_id", "publication_id", "population", "measure") || any(!is.na(s[[f]]))
    s[c("series_key", Filter(keep, c("series_id", "measure_id", "publication_id", measure_fields, dims)))]
  })
  observations$series_id <- unlist(lapply(series, `[[`, "series_id"), use.names = FALSE)[match(observations$series_key, unlist(lapply(series, `[[`, "series_key"), use.names = FALSE))]
  series <- lapply(series, function(s) s[names(s) != "series_key"])
  catalogue <- c("measure_id", "publication_id", measure_fields)
  measures <- bind(lapply(series, function(s) lapply(stats::setNames(catalogue, catalogue), function(f) s[[f]] %||% rep(NA_character_, nrow(s)))))
  measures <- dplyr::count(measures, dplyr::across(dplyr::all_of(catalogue)), name = "series")
  sources <- dplyr::mutate(dplyr::filter(source_metadata_df, sheet_sha256 %in% observations$sheet_sha256), dplyr::across(dplyr::everything(), as.character),
                           release_id = dplyr::coalesce(source_release_id, paste(publication_id, asset_year, sep = "-")), release = dplyr::coalesce(release, asset_year), sheet = sheets)
  sources <- dplyr::left_join(sources[unlist(spec$source_fields)], bind(purrr::map(parts, "title")), by = "sheet_sha256")
  list(observations = observations[c("series_id", "period", "reference_date", "published_text", "sheet_sha256", "address", "derived")],
       series = series, measures = measures, sources = sources)
}
