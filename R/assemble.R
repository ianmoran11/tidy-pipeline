# Stage 5: turn the per-sheet records into linked tables for analysis.
#   observations  one row per published value (cell), linked to a series
#   series        one row per publication + measure fields + dimension values
#   measures      one row per publication + measure fields (the measure catalogue)
#   sources       one row per sheet: publication, release, workbook, sheet, title
# A series is everything that identifies a value except its period. IDs are the
# first 16 hex digits of a SHA-256 of the identifying text, so they are stable
# across rebuilds. See integration/README.md.
assemble <- function(data_identified, source_metadata_df, integration_spec) {
  spec <- integration_spec; skip <- unlist(c(spec$cell_fields, spec$observation_fields))
  hash <- function(x) substr(as.character(openssl::sha256(x)), 1, 16)
  bind <- function(x, ...) tibble::as_tibble(data.table::setDF(data.table::rbindlist(x, ...)))  # setDF() avoids copying the table
  parts <- purrr::map(data_identified, function(s) {
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
                      title = paste(unlist(s$sheet_metata[["table_title"]]), collapse = " ")))
  })
  parts <- purrr::compact(parts)
  observations <- bind(purrr::map(parts, "observations"))
  series <- bind(purrr::map(parts, "series"), fill = TRUE)
  series <- series[!duplicated(series$series_key), ]
  measure_fields <- intersect(unlist(spec$measure_fields), names(series))
  series$measure_id <- hash(do.call(paste, c(list("publication_id", series$publication_id), as.list(series[measure_fields]), sep = "|")))
  series$series_id <- hash(series$series_key)
  observations$series_id <- series$series_id[match(observations$series_key, series$series_key)]
  dims <- setdiff(names(series), c("series_key", "series_id", "measure_id", "publication_id", measure_fields))
  dims <- c(intersect(unlist(spec$dimension_order), dims), sort(setdiff(dims, unlist(spec$dimension_order))))
  series <- series[c("series_id", "measure_id", "publication_id", measure_fields, dims)]
  measures <- dplyr::count(series, dplyr::across(dplyr::all_of(c("measure_id", "publication_id", measure_fields))), name = "series")
  sources <- dplyr::mutate(dplyr::filter(source_metadata_df, sheet_sha256 %in% observations$sheet_sha256), dplyr::across(dplyr::everything(), as.character),
                           release_id = dplyr::coalesce(source_release_id, paste(publication_id, asset_year, sep = "-")), release = dplyr::coalesce(release, asset_year), sheet = sheets)
  sources <- dplyr::left_join(sources[unlist(spec$source_fields)], bind(purrr::map(parts, "title")), by = "sheet_sha256")
  list(observations = observations[c("series_id", "period", "reference_date", "published_text", "sheet_sha256", "address", "derived")],
       series = series, measures = measures, sources = sources)
}
