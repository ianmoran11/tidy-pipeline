# Stage 8: one value per series and period across releases. Every release's value is
# kept. is_latest marks exactly one observation per series and period: the one from
# the most recent release, preferring a number over a symbol within that release.
# Releases are ordered by the latest reference date in their own data (their
# release_end; the spec can override it), then by release date.
# differs_from_latest marks values another release has since revised: a different number
# or, where neither has one, a different status. Text alone ("np" vs "n.p.", a quality
# asterisk) isn't a revision.
reconcile <- function(observations, sources, reconcile_spec) {
  spec <- reconcile_spec
  obs <- dplyr::left_join(observations, sources[c("sheet_sha256", "release_id", "release_date")], by = "sheet_sha256")
  releases <- dplyr::summarise(dplyr::group_by(obs, release_id), release_date = dplyr::first(release_date),
                               release_end = if (all(is.na(reference_date))) NA_character_ else max(reference_date, na.rm = TRUE))
  overrides <- unlist(spec$release_end_overrides)
  releases$release_end <- dplyr::coalesce(unname(overrides[releases$release_id]), releases$release_end)
  obs <- dplyr::left_join(dplyr::select(obs, -release_date), releases, by = "release_id")
  obs <- dplyr::arrange(obs, series_id, period, dplyr::desc(release_end), dplyr::desc(release_date), is.na(value), sheet_sha256, address)
  # vectorised over the sorted rows: each series-and-period group's first row is its latest
  key <- paste(obs$series_id, obs$period); first <- !duplicated(key); group <- cumsum(first); top <- which(first)[group]
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  v <- obs$value; s <- obs$value_status; unchanged <- same(v, v[top]) & (!is.na(v) | same(s, s[top]))
  obs$n_releases <- tabulate(group[!duplicated(paste(key, obs$release_id))], nbins = max(group, 0))[group]
  obs$is_latest <- first
  obs$differs_from_latest <- obs$release_id != obs$release_id[top] & !unchanged
  dplyr::select(obs, -release_date, -release_end)
}
