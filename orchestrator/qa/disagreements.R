# Show cell-level disagreements with the texts of the missing/extra label cells.
# Usage: Rscript orchestrator/qa/disagreements.R <batch> <publication_id> [n_sheets] [n_cells]   (after compare_reference.R)
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
args <- commandArgs(TRUE)
name <- args[1]; pub <- args[2]; n_sheets <- as.integer(args[3] %||% 3); n_cells <- as.integer(args[4] %||% 4)
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
res <- readRDS(sprintf("orchestrator/qa/cache/compare_results_%s.rds", name)) %>% filter(publication_id == pub, has_reference)
cells <- readRDS(sprintf("orchestrator/qa/cache/compare_cells_%s.rds", name))
for (i in seq_len(min(n_sheets, nrow(res)))) {
  r <- res %>% arrange(desc(missing + extra + different + missing_sheet_meta)) %>% slice(i)
  mm <- m %>% filter(sheet_sha256 == r$sheet_sha256)
  sc <- tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", mm$xlsx_file), sheets = mm$sheets) %>%
    mutate(v = coalesce(character, as.character(numeric))) %>% select(address, v)
  txt <- function(a) paste0(a, "=", str_trunc(sc$v[match(a, sc$address)] %||% "", 45), collapse = "; ")
  cat(sprintf("\n=== %s | %s | exact %d, sheet-meta %d, extra %d, different %d | ref cells missed %d %s | recipe-only %d %s\n",
              r$sheet, substr(r$sheet_sha256, 1, 8), r$exact, r$missing_sheet_meta, r$extra, r$different,
              r$ref_cells_not_in_recipe, paste(unlist(r$ref_not_in_recipe_examples), collapse = ","),
              r$recipe_cells_not_in_ref, paste(unlist(r$recipe_not_in_ref_examples), collapse = ",")))
  d <- cells %>% filter(sheet_sha256 == r$sheet_sha256, outcome != "exact")
  pats <- d %>% mutate(pattern = paste(outcome, "| missing:", map_chr(missing, ~ paste(sort(.x), collapse = ",")),
                                       "| extra:", map_chr(extra, ~ paste(sort(.x), collapse = ",")))) %>%
    count(pattern, sort = TRUE)
  cat("  distinct disagreement patterns:", nrow(pats), "\n")
  for (j in seq_len(min(n_cells, nrow(d)))) {
    x <- d[j * max(1, floor(nrow(d) / n_cells)) - (max(1, floor(nrow(d) / n_cells)) - 1), ]
    cat(sprintf("  %s (%s) %s\n     missing: %s\n     extra:   %s\n", x$address, x$raw_value_text, x$outcome,
                txt(x$missing[[1]]), txt(x$extra[[1]])))
  }
}
