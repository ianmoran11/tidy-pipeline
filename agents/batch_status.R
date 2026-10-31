#!/usr/bin/env Rscript
# Progress of a batch: Rscript agents/batch_status.R agents/batch-abs-1000.txt
suppressPackageStartupMessages({library(dplyr); library(purrr); library(stringr); library(readr)})
batch <- readLines(commandArgs(TRUE)[1])
m <- read_csv("source_metadata.csv", col_types = cols(.default = col_character()), trim_ws = FALSE, progress = FALSE) %>% filter(xlsx_file %in% batch)
status <- map_chr(m$sheet_sha256, function(sha) {
  p <- file.path("tidy-recipes", paste0(sha, ".json"))
  if (!file.exists(p)) "missing" else tryCatch(jsonlite::read_json(p)$status %||% "draft", error = function(e) "invalid json")
})
# runs.csv lines: finished,xlsx_file,exit,seconds[,run_id] (older lines have no run_id)
fields <- str_split(readLines("agents/runs.csv", warn = FALSE), ",")
runs <- tibble(xlsx_file = map_chr(fields, 2), exit = map_chr(fields, 3), run_id = map_chr(fields, ~ .x[5] %||% NA_character_)) %>%
  filter(xlsx_file %in% batch)
cat(sprintf("workbooks finished: %d/%d (non-zero exits: %d) | sheets: %s\n", n_distinct(runs$xlsx_file), length(batch),
            sum(runs$exit != "0"), paste(names(table(status)), table(status), sep = " ", collapse = ", ")))
# provider errors in this batch's logs (rate limits, usage limits, aborted turns)
errs <- map_dfr(runs$run_id, function(id) {
  f <- file.path("agents/logs", paste0(id, ".jsonl"))
  if (!file.exists(f)) return(NULL)
  l <- readLines(f, warn = FALSE)
  e <- str_match(l[str_detect(l, '"errorMessage"')], '"errorMessage":"([^"]{0,160})')[, 2]
  if (length(e)) tibble(run_id = id, error = e) else NULL
})
if (nrow(errs)) { cat("provider errors:\n"); print(count(errs, error = str_trunc(error, 120), sort = TRUE)) }
