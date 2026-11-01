# Checks for `observations` (reconcile() output), against observations_typed:
#   - the same cells keep the same values;
#   - every observation has a release;
#   - exactly one value per series and period is latest, and n_releases is right;
#   - revision flags are consistent with the latest value.
# It also reports values in one release that can't be told apart (ISSUES.md I26).
# Each test returns its failures (none when it passes). A failed "error" test stops the
# target; "warning" results are only reported. Returns one row per test.
check_observations <- function(observations, observations_typed) {
  new <- observations; old <- observations_typed
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  key <- paste(new$series_id, new$period)

  # The same cells, each with the same series, period, text, value and status
  rows_unchanged <- function() {
    i <- match(paste(old$sheet_sha256, old$address), paste(new$sheet_sha256, new$address))
    cols <- c("series_id", "period", "published_text", "value", "value_status")
    changed <- !is.na(i) & !Reduce(`&`, lapply(cols, function(col) same(old[[col]], new[[col]][i])))
    c(sprintf("%d rows; observations_typed had %d", nrow(new), nrow(old))[nrow(new) != nrow(old)],
      sprintf("cell %s %s is missing", old$sheet_sha256[is.na(i)], old$address[is.na(i)]),
      sprintf("cell %s %s changed", old$sheet_sha256[changed], old$address[changed]))
  }
  # Every observation has a release
  releases_present <- function() sprintf("cell %s %s has no release_id", new$sheet_sha256[is.na(new$release_id)], new$address[is.na(new$release_id)])
  # Exactly one latest value per series and period
  one_latest_per_series_period <- function() {
    latest <- key[new$is_latest]
    c(sprintf("series and period %s has more than one latest value", unique(latest[duplicated(latest)])),
      sprintf("series and period %s has no latest value", setdiff(unique(key), latest)))
  }
  # n_releases is the number of distinct releases for its series and period
  release_counts_correct <- function() {
    group <- match(key, unique(key))
    actual <- tabulate(group[!duplicated(paste(key, new$release_id))], nbins = max(group, 0))[group]
    bad <- new$n_releases != actual; first <- bad & !duplicated(ifelse(bad, key, NA))
    sprintf("series and period %s: n_releases %d, actually %d", key[first], new$n_releases[first], actual[first])
  }
  # The latest value is never flagged as revised; earlier values are flagged exactly when
  # they come from another release and their text differs from the latest
  revision_flags_consistent <- function() {
    latest <- new[new$is_latest, ]
    j <- match(key, paste(latest$series_id, latest$period))
    expected <- new$release_id != latest$release_id[j] & !same(new$published_text, latest$published_text[j])
    bad <- !((new$differs_from_latest == expected) %in% TRUE)
    sprintf("cell %s %s: differs_from_latest is %s", new$sheet_sha256[bad], new$address[bad], new$differs_from_latest[bad])
  }
  # Within one release, a series and period has at most one distinct number (known gaps: ISSUES.md I26)
  values_distinguishable <- function() {
    p <- new[new$value_status == "published", ]
    k <- paste(p$release_id, p$series_id, p$period); p <- p[k %in% k[duplicated(k)], ]  # only these can differ
    d <- dplyr::filter(dplyr::count(dplyr::distinct(p, release_id, series_id, period, published_text), release_id, series_id, period), n > 1)
    sprintf("%s: series %s, %s has %d different numbers", d$release_id, d$series_id, d$period, d$n)
  }

  severity <- c(rows_unchanged = "error", releases_present = "error", one_latest_per_series_period = "error",
                release_counts_correct = "error", revision_flags_consistent = "error", values_distinguishable = "warning")
  results <- purrr::imap_dfr(severity, function(level, test) {
    failures <- tryCatch(get(test, mode = "function")(), error = function(e) sprintf("test could not run: %s", conditionMessage(e)))
    tibble::tibble(target = "observations", sheet_sha256 = NA_character_, test = test, severity = level,
                   passed = length(failures) == 0, n_failed = length(failures), examples = paste(utils::head(failures, 5), collapse = "; "))
  })
  failed <- results[!results$passed & results$severity == "error", ]
  if (nrow(failed)) stop("observations failed checks: ", paste0(failed$test, " (", failed$n_failed, "): ", failed$examples, collapse = " | "), call. = FALSE)
  results
}
