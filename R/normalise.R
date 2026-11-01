# Replace dimension names and labels in one sheet's tidy output (one branch of the
# data target) with canonical versions from normalisation/normalisation_spec.json:
#   dimension_names: {"raw dimension name": "canonical name"}
#   clean: [{"pattern": regex, "replace": text}], applied in order to every label
#          (whitespace, footnote markers) and to the value maps' keys
#   values: {"canonical dimension name": {"raw label": "canonical label"}}
# Names are renamed first, so value maps are keyed by canonical names. Anything
# not in the spec is left as it is; row, col, address, .value and sheet-level
# meta_data are never changed.
normalise <- function(sheet_result, normalisation_spec) {
  name_map <- unlist(normalisation_spec$dimension_names)
  clean <- function(x) { for (rule in normalisation_spec$clean) x <- gsub(rule[["pattern"]], rule[["replace"]], x, perl = TRUE); x }
  value_maps <- lapply(normalisation_spec$values, function(m) { m <- unlist(m); names(m) <- clean(names(m)); m[!duplicated(names(m))] })
  fixed <- c("row", "col", "address", ".value")

  # labels: one record, or a table's meta_data_list (a named list of labels)
  normalise_labels <- function(labels) {
    if (length(labels) == 0) return(labels)
    old <- names(labels)
    renamed <- !old %in% fixed & old %in% names(name_map)
    names(labels)[renamed] <- name_map[old[renamed]]
    if (anyDuplicated(names(labels))) {
      stop("Renaming gives duplicate dimension names: ", paste(old, collapse = ", "))
    }
    for (dim in setdiff(names(labels), fixed)) labels[[dim]] <- clean(labels[[dim]])
    for (dim in intersect(setdiff(names(labels), fixed), names(value_maps))) {
      value <- labels[[dim]]
      mapped <- !is.na(value) & value %in% names(value_maps[[dim]])
      value[mapped] <- value_maps[[dim]][value[mapped]]
      labels[[dim]] <- unname(value)
    }
    labels
  }

  sheet_result$tables <- lapply(sheet_result$tables, function(table) {
    table$tidy_table_list <- lapply(table$tidy_table_list, normalise_labels)
    table$meta_data_list <- normalise_labels(table$meta_data_list)
    table
  })
  sheet_result
}
