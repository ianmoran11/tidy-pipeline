suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c", sheet_index = "i"), trim_ws = FALSE)
files <- list.files("tidy-recipes", pattern = "^[0-9a-f]{64}\\.json$", full.names = TRUE)
r <- map_dfr(files, function(p) {
  s <- jsonlite::read_json(p)
  tibble(sheet_sha256 = sub("\\.json$", "", basename(p)), kind = s$kind, status = s$status,
         tables = length(s$tables %||% list()), records = s$validation$records %||% NA_integer_,
         method = s$generation$method %||% NA, template = !is.null(s$template_from),
         notes = nchar(s$agent_notes %||% ""), fast = isTRUE(s$generation$agent$fast_mode))
}) %>% left_join(m %>% select(sheet_sha256, sheets, publication_id, xlsx_file, normalization), by = "sheet_sha256")
saveRDS(r, "orchestrator/qa/cache/recipes.rds")
cat("recipes:", nrow(r), " workbooks:", n_distinct(r$xlsx_file), " records:", sum(r$records, na.rm = TRUE), "\n")
print(count(r, kind, status))
print(count(r, method, template))
print(r %>% filter(kind == "data") %>% group_by(publication_id) %>%
  summarise(sheets = n(), workbooks = n_distinct(xlsx_file), tables = sum(tables), records = sum(records),
            median_tables = median(tables), max_tables = max(tables), normalized = sum(!is.na(normalization))), width = 200)
