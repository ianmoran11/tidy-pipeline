# What harmonise() could not fill in, to guide edits to harmonisation_spec.json:
# records without period, reference_date or measure by publication, period labels
# with no reference date, and how many records each derived dimension came from.
harmonisation_report <- function(data_harmonised) {
  records <- dplyr::bind_rows(lapply(data_harmonised, function(s) {
    recs <- unlist(lapply(s$tables, `[[`, "tidy_table_list"), recursive = FALSE)
    if (!length(recs)) return(NULL)
    field <- function(name) vapply(recs, function(r) as.character(r[[name]] %||% NA)[1], "")
    tibble::tibble(publication_id = s$source$publication_id, period = field("period"),
                   reference_date = field("reference_date"), measure = field("measure"), derived = field(".derived"))
  }))
  list(
    by_publication = records %>%
      dplyr::group_by(publication_id) %>%
      dplyr::summarise(records = dplyr::n(), no_period = sum(is.na(period)), no_reference_date = sum(is.na(reference_date)),
                       no_measure = sum(is.na(measure)), with_derived = sum(derived != ""), .groups = "drop"),
    undated_periods = records %>% dplyr::filter(!is.na(period), is.na(reference_date)) %>% dplyr::count(publication_id, period),
    derived = records %>% dplyr::filter(derived != "") %>% tidyr::separate_rows(derived, sep = ",") %>%
      dplyr::count(publication_id, dimension = derived)
  )
}
