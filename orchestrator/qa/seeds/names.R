suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
source("R/expand_excel_range.R"); source("orchestrator/qa/recipe_labels.R")
rs <- readRDS("orchestrator/qa/cache/recipes.rds") %>% filter(kind == "data")
all <- map_dfr(seq_len(nrow(rs)), function(i) {
  r <- rs[i, ]
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  labs <- recipe_labels(spec, sheet_cells(r))
  kinds <- bind_rows(
    map_dfr(spec$tables, function(t) tibble(dim = map_chr(t$headers, "name"), role = paste0("header ", map_chr(t$headers, "direction")))),
    map_dfr(spec$tables, function(t) tibble(dim = map_chr(t$meta_data %||% list(), "name"), role = "table meta"))) %>% distinct()
  labs %>% distinct(dim, label) %>% left_join(kinds, by = "dim", relationship = "many-to-many") %>% mutate(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256)
})
saveRDS(all, "orchestrator/qa/cache/names.rds")
s <- all %>% group_by(dim) %>% summarise(sheets = n_distinct(sheet_sha256), pubs = paste(unique(str_remove(publication_id, "-australia|-justice")), collapse = ","),
  roles = paste(unique(role), collapse = ","), n_labels = n_distinct(label),
  labels = str_trunc(paste(head(unique(str_trunc(label, 28)), 7), collapse = " | "), 150), .groups = "drop") %>% arrange(desc(sheets))
options(width = 300)
print(as.data.frame(s), right = FALSE)
