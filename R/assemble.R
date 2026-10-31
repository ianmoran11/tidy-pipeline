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
  parts <- purrr::map(data_identified, function(s) {
    recs <- unlist(purrr::map(s$tables, "tidy_table_list"), recursive = FALSE)
    if (!length(recs)) return(NULL)
    dims <- purrr::map(recs, function(r) { d <- unlist(r[setdiff(names(r), skip)]); d[order(names(d))] })
    key <- paste0("publication_id=", s$source$publication_id, "|", vapply(dims, function(d) paste(names(d), d, sep = "=", collapse = "|"), ""))
    field <- function(f) vapply(recs, function(r) as.character(r[[f]] %||% NA_character_)[1], "")
    first <- which(!duplicated(key))
    list(observations = tibble::tibble(series_key = key, period = field("period"), reference_date = field("reference_date"),
                                       published_text = field(".value"), sheet_sha256 = s$source$sheet_sha256, address = field("address"), derived = field(".derived")),
         series = data.table::rbindlist(purrr::map(first, ~ as.list(c(series_key = key[.x], publication_id = s$source$publication_id, dims[[.x]]))), fill = TRUE),
         title = tibble::tibble(sheet_sha256 = s$source$sheet_sha256, subject = s$source$subject %||% NA_character_,
                                title = paste(unlist(s$sheet_metata[["table_title"]]), collapse = " ")))
  })
  parts <- purrr::compact(parts)
  observations <- data.table::rbindlist(purrr::map(parts, "observations"))
  series <- tibble::as_tibble(data.table::rbindlist(purrr::map(parts, "series"), fill = TRUE))
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
  sources <- dplyr::left_join(sources[unlist(spec$source_fields)], dplyr::bind_rows(purrr::map(parts, "title")), by = "sheet_sha256")
  list(observations = tibble::as_tibble(observations)[c("series_id", "period", "reference_date", "published_text", "sheet_sha256", "address", "derived")],
       series = series, measures = measures, sources = sources)
}
