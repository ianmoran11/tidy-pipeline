# What still stands in the way of analysis, by publication: values that can't be
# told apart (same series, period and release, different published text: either two
# different numbers, or a number and a symbol such as "na"), series without a
# population or measure, value statuses, and unrecognised value text.
integration_report <- function(observations, series, sources) {
  series <- dplyr::bind_rows(lapply(series, `[`, c("publication_id", "population", "measure")))  # one table per publication
  obs <- dplyr::mutate(observations, publication_id = sources$publication_id[match(sheet_sha256, sources$sheet_sha256)])
  key <- paste(obs$release_id, obs$series_id, obs$period)  # only one published more than once can conflict
  conflicts <- dplyr::summarise(dplyr::group_by(obs[key %in% key[duplicated(key)], ], publication_id, release_id, series_id, period), records = dplyr::n(),
    texts = dplyr::n_distinct(published_text), numbers = dplyr::n_distinct(published_text[value_status == "published"]), .groups = "drop")
  conflicts <- dplyr::filter(conflicts, texts > 1)
  list(
    by_publication = dplyr::summarise(dplyr::group_by(obs, publication_id), records = dplyr::n(), series = dplyr::n_distinct(series_id),
      latest = sum(is_latest), in_2plus_releases = sum(n_releases > 1 & is_latest), revised = sum(differs_from_latest),
      blank = sum(value_status == "blank"), symbols = sum(!value_status %in% c("published", "blank")), unrecognised = sum(value_status == "unrecognised")),
    identity_conflicts = dplyr::summarise(dplyr::group_by(conflicts, publication_id), keys = dplyr::n(), records = sum(records),
      numbers_differ = sum(numbers > 1), number_vs_symbol = sum(numbers <= 1)),
    conflicts = conflicts,
    missing = dplyr::summarise(dplyr::group_by(series, publication_id), series = dplyr::n(),
      no_population = sum(is.na(population)), no_measure = sum(is.na(measure))),
    statuses = dplyr::count(obs, publication_id, value_status),
    unrecognised = dplyr::count(dplyr::filter(obs, value_status == "unrecognised"), publication_id, published_text, sort = TRUE))
}
