# Values that still can't be told apart (same series, period and release, different
# published text), with each cell's sheet metadata, to find what identifies them.
# Usage: Rscript orchestrator/qa/integration_conflicts.R <publication_id> [n_examples] [numbers|all]
suppressMessages({library(dplyr); library(purrr); library(stringr)})
args <- commandArgs(TRUE); pub <- args[1]; n <- as.integer(args[2] %||% 3); kind <- args[3] %||% "numbers"
obs <- targets::tar_read(observations); it <- targets::tar_read(integrated); src <- it$sources; ser <- it$series
cf <- targets::tar_read(integration_gaps)$conflicts %>% filter(publication_id == pub, kind == "all" | numbers > 1)
cat(nrow(cf), "conflicting keys\n")
x <- obs %>% semi_join(cf, by = c("release_id", "series_id", "period")) %>% left_join(src %>% select(sheet_sha256, title, xlsx_file, sheet), by = "sheet_sha256")
tp <- x %>% group_by(release_id, series_id, period) %>% summarise(t = paste(sort(unique(str_trunc(title, 80))), collapse = "  <>  "), .groups = "drop") %>% count(t, sort = TRUE)
cat("\nmost common title combinations:\n"); cat(sprintf("%6d  %s", head(tp$n, 8), head(tp$t, 8)), sep = "\n")
h <- targets::tar_read(data_identified)
for (k in seq_len(min(n, nrow(cf)))) {
  y <- x %>% semi_join(cf[k, ], by = c("release_id", "series_id", "period"))
  s <- ser %>% filter(series_id == cf$series_id[k]); s <- s[, colSums(is.na(s)) == 0]
  cat("\n#### period", cf$period[k], "| labels:", paste(names(s)[-(1:3)], unlist(s[1, -(1:3)]), sep = "=", collapse = " | "), "\n")
  for (j in seq_len(nrow(y))) cat("  ", y$address[j], "=", y$published_text[j], "|", sub("^[0-9a-f]{64}--", "", y$xlsx_file[j]), y$sheet[j], "|", str_trunc(y$title[j], 140), "\n")
}
