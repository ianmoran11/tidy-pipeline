# Texts of the labels behind each kind of disagreement, and the database cells no recipe covers.
# Usage: Rscript orchestrator/qa/ref_gaps.R <batch>   (after compare_reference.R)
suppressMessages({library(dplyr); library(purrr); library(stringr); library(DBI); library(RSQLite)})
name <- commandArgs(TRUE)[1]
source("R/expand_excel_range.R")
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
cells <- readRDS(sprintf("orchestrator/qa/cache/compare_cells_%s.rds", name)) %>% left_join(m %>% select(sheet_sha256, sheets, xlsx_file, xlsx_path, source_sha256, publication_id), by = "sheet_sha256")
res <- readRDS(sprintf("orchestrator/qa/cache/compare_results_%s.rds", name)) %>% filter(has_reference)
# 1. missing labels: what text is missing?
cache <- list()
txt <- function(path, sh, a) { k <- paste(path, sh); if (is.null(cache[[k]])) cache[[k]] <<- tidyxl::xlsx_cells(path, sheets = sh) %>% mutate(v = coalesce(character, as.character(numeric))); s <- cache[[k]]; s$v[match(a, s$address)] }
miss <- cells %>% filter(outcome %in% c("missing labels", "different labels"), publication_id %in% c("criminal-courts-australia", "recorded-crime-offenders", "prisoners-australia")) %>%
  group_by(publication_id, sheet_sha256, sheets, xlsx_path) %>% slice_sample(n = 3) %>% ungroup()
miss$missing_text <- pmap_chr(list(miss$xlsx_path, miss$sheets, miss$missing), function(p, s, a) paste(str_trunc(txt(p, s, a), 40), collapse = " + "))
miss$extra_text <- pmap_chr(list(miss$xlsx_path, miss$sheets, miss$extra), function(p, s, a) if (length(a)) paste(str_trunc(txt(p, s, a), 40), collapse = " + ") else "")
cat("== most common missing label texts (sampled cells)\n")
print(miss %>% count(publication_id, missing_text, sort = TRUE) %>% group_by(publication_id) %>% slice_head(n = 6) %>% ungroup(), n = 30, width = 200)
# 2. reference cells not in recipes: blank or not?
con <- dbConnect(SQLite(), "tidy-data-asset-status.sqlite3", flags = SQLITE_RO)
cov <- map_dfr(which(res$ref_cells_not_in_recipe > 0), function(i) {
  r <- m %>% filter(sheet_sha256 == res$sheet_sha256[i])
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  vals <- unique(unlist(map(spec$tables, ~ expand_excel_range(.x$values_range))))
  q <- dbGetQuery(con, "SELECT source_cell AS address, raw_value_text, value_status FROM source_cell_observation WHERE source_workbook_digest = ? AND source_sheet = ?", params = list(paste0("sha256:", r$source_sha256), r$sheets))
  sc <- tidyxl::xlsx_cells(r$xlsx_path, sheets = r$sheets) %>% transmute(address, v = coalesce(character, as.character(numeric)))
  q %>% filter(!address %in% vals) %>% left_join(sc, by = "address") %>% mutate(publication_id = r$publication_id, sheet = r$sheets, sheet_sha256 = r$sheet_sha256)
})
dbDisconnect(con)
cov <- bind_rows(tibble(address = character(), value_status = character(), v = character(), publication_id = character()), cov)
cat("\n== reference cells not in recipes:", nrow(cov), "\n")
print(cov %>% mutate(kind = if_else(is.na(v), "blank in sheet", paste("value:", str_trunc(v, 10)))) %>% count(publication_id, value_status, kind, sort = TRUE) %>% head(15), width = 200)
saveRDS(cov, sprintf("orchestrator/qa/cache/ref_missed_%s.rds", name))
