# Pick unfinished workbooks for the next agent batch, most recent years first.
# Usage: Rscript orchestrator/qa/select_batch.R agents/<batch>.txt [max_sheets] [publication_id regex]
# Run `Rscript agents/queue.R build` first so queue.csv is current.
suppressMessages({library(dplyr); library(stringr)})
args <- commandArgs(TRUE); max_sheets <- as.numeric(args[2] %||% Inf); pubs <- args[3] %||% "."
q <- readr::read_csv("agents/queue.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c")) %>%
  mutate(across(c(sheets, validated, needs_review, missing), as.integer), done = done == "TRUE")
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE) %>% distinct(xlsx_file, publisher)
todo <- q %>% left_join(m, by = "xlsx_file") %>% filter(str_detect(publication_id, pubs), !done) %>%
  mutate(year = as.integer(str_extract(coalesce(period, xlsx_file), "(19|20)[0-9]{2}"))) %>%
  arrange(desc(year), publication_id, xlsx_file) %>%
  mutate(cumulative = cumsum(missing))
sel <- todo %>% filter(cumulative <= max_sheets | row_number() == 1)
writeLines(sel$xlsx_file, args[1])
cat("matching workbooks not done:", nrow(todo), "with", sum(todo$missing), "sheets to do\n")
cat("selected:", nrow(sel), "workbooks,", sum(sel$missing), "sheets\n")
print(sel %>% group_by(publication_id, year) %>% summarise(workbooks = n(), sheets = sum(missing), .groups = "drop") %>% arrange(desc(year), publication_id), n = 40)
cat("largest workbooks:", paste(head(sort(sel$missing, decreasing = TRUE), 5), collapse = ", "), "sheets\n")
