# Status and validator failures of every recipe in a batch; first step of the batch review.
# Usage: Rscript orchestrator/qa/batch_recipes.R agents/<batch>.txt  -> cache/<batch>_recipes.rds
suppressMessages({library(dplyr); library(purrr); library(stringr)})
args <- commandArgs(TRUE)
name <- tools::file_path_sans_ext(basename(args[1]))   # batch name, e.g. batch-abs-rest
batch <- readLines(args[1])
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE) %>% filter(xlsx_file %in% batch)
r <- map_dfr(seq_len(nrow(m)), function(i) {
  p <- file.path("tidy-recipes", paste0(m$sheet_sha256[i], ".json"))
  if (!file.exists(p)) return(tibble(sheet_sha256 = m$sheet_sha256[i], status = "missing"))
  s <- jsonlite::read_json(p)
  tibble(sheet_sha256 = m$sheet_sha256[i], publication_id = m$publication_id[i], sheet = m$sheets[i], sheets = m$sheets[i], xlsx_file = m$xlsx_file[i],
         kind = s$kind, status = s$status, records = s$validation$records %||% NA, template = !is.null(s$template_from),
         new_dims = length(s$new_dimensions %||% list()),
         failures = str_flatten(unlist(s$validation$failures %||% list()), " || "), notes = s$agent_notes %||% "")
})
saveRDS(r, sprintf("orchestrator/qa/cache/%s_recipes.rds", name))
print(count(r, kind, status))
cat("records:", sum(r$records, na.rm = TRUE), "| from a template:", sum(r$template, na.rm = TRUE), "| declaring new dimensions:", sum(r$new_dims > 0, na.rm = TRUE), "\n\n")
cat("needs_review by failure type:\n")
nr <- r %>% filter(status == "needs_review") %>% mutate(type = case_when(
  str_detect(failures, "numeric cells") & kind != "data" ~ "non-data sheet contains numbers",
  str_detect(failures, "blank cells in values_range") ~ "blank cells in values",
  str_detect(failures, "lack a header label") ~ "records missing labels",
  str_detect(failures, "not in values, headers or meta_data") ~ "cells in table area not accounted for",
  str_detect(failures, "outside every table") ~ "numbers outside tables",
  TRUE ~ "other"))
print(count(nr, publication_id, kind, type))
print(as.data.frame(nr %>% transmute(sheet, wb = str_trunc(sub("^[0-9a-f]{64}--", "", xlsx_file), 45), type, f = str_trunc(failures, 110))), row.names = FALSE)
cat("\ndrafts:\n"); print(as.data.frame(r %>% filter(status == "draft") %>% transmute(sheet, wb = sub("^[0-9a-f]{64}--", "", xlsx_file), sheet_sha256)), row.names = FALSE)
