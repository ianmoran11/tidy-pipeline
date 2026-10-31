# Stage 8: one value per series and period across releases. Every release's value is
# kept. is_latest marks exactly one observation per series and period: the one from
# the most recent release, preferring a number over a symbol within that release.
# Releases are ordered by the latest reference date in their own data (their
# release_end; the spec can override it), then by release date.
# differs_from_latest marks values another release has since revised.
reconcile <- function(observations, sources, reconcile_spec) {
  spec <- reconcile_spec
  obs <- dplyr::left_join(observations, sources[c("sheet_sha256", "release_id", "release_date")], by = "sheet_sha256")
  releases <- dplyr::summarise(dplyr::group_by(obs, release_id), release_date = dplyr::first(release_date),
                               release_end = if (all(is.na(reference_date))) NA_character_ else max(reference_date, na.rm = TRUE))
  overrides <- unlist(spec$release_end_overrides)
  releases$release_end <- dplyr::coalesce(unname(overrides[releases$release_id]), releases$release_end)
  obs <- dplyr::left_join(dplyr::select(obs, -release_date), releases, by = "release_id")
  obs <- dplyr::arrange(obs, series_id, period, dplyr::desc(release_end), dplyr::desc(release_date), is.na(value), sheet_sha256, address)
  obs <- dplyr::mutate(dplyr::group_by(obs, series_id, period), n_releases = dplyr::n_distinct(release_id), is_latest = dplyr::row_number() == 1,
                       differs_from_latest = release_id != release_id[1] & !(published_text %in% published_text[1]))
  dplyr::select(dplyr::ungroup(obs), -release_date, -release_end)
}
