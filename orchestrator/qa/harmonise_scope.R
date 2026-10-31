# Scope analysis for a harmonisation stage (read-only).
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
d <- targets::tar_read(data_normalised)
files <- targets::tar_read(recipe_files)
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
sha <- sub("\\.json$", "", basename(files))
info <- m[match(sha, m$sheet_sha256), c("sheet_sha256", "publication_id", "sheets", "xlsx_file", "reference_period", "asset_year")]
fixed <- c("row", "col", "address", ".value")

states <- c("New South Wales", "Victoria", "Queensland", "South Australia", "Western Australia", "Tasmania", "Northern Territory", "Australian Capital Territory")
state_re <- regex(paste0("\\b(", paste(states, collapse = "|"), ")\\b"), ignore_case = TRUE)
period_re <- "\\b(19|20)\\d{2}(–\\d{2})?\\b"
court_re <- regex("\\b(Higher Courts?|Magistrates'? Courts?|Children's Courts?|All Courts)\\b", ignore_case = TRUE)

sheets <- map_dfr(seq_along(d), function(i) {
  s <- d[[i]]
  if (!length(s$tables)) return(NULL)
  title <- paste(c(unlist(s$sheet_metata[intersect(names(s$sheet_metata), c("table_title", "table_subtitle", "sheet_description"))]),
                   unlist(map(s$tables, ~ .x$meta_data_list$table_title))), collapse = " / ")
  rec_dims <- unique(unlist(map(s$tables, ~ setdiff(unique(unlist(map(.x$tidy_table_list, names))), fixed))))
  meta_dims <- unique(unlist(map(s$tables, ~ names(.x$meta_data_list))))
  dims <- union(rec_dims, meta_dims)
  title_states <- unique(str_to_lower(str_extract_all(title, state_re)[[1]]))
  tibble(i = i, publication_id = info$publication_id[i], sheet = info$sheets[i], title = title,
         records = sum(map_int(s$tables, ~ length(.x$tidy_table_list))),
         tables_with_meta = sum(map_lgl(s$tables, ~ length(setdiff(names(.x$meta_data_list), c("table_title", "notes", "source", "table_subtitle"))) > 0)),
         has_state = "state" %in% dims, title_states = length(title_states), title_state = paste(title_states, collapse = ","),
         has_period = "period" %in% dims, title_period = str_extract(title, "(19|20)\\d{2}(–\\d{2})?(?!.*(19|20)\\d{2})"),
         title_period_range = str_detect(title, "(19|20)\\d{2}(–\\d{2})? to (19|20)\\d{2}"),
         has_court_level = "court_level" %in% dims, title_court = str_extract(title, court_re),
         has_estimate_type = "estimate_type" %in% dims, title_se = str_detect(title, regex("standard error|relative standard error|RSE", ignore_case = TRUE)),
         stacked = any(c("characteristic", "category") %in% dims),
         dims = list(dims))
})
saveRDS(sheets, "orchestrator/qa/cache/harmonise_sheets.rds")
cat("data sheets:", nrow(sheets), "| records:", sum(sheets$records), "\n\n")

cat("== 1. constants in the title, missing as a dimension\n")
cat(sprintf("state: %d sheets (%d records) name exactly one state in the title but have no state dimension\n",
            sum(!sheets$has_state & sheets$title_states == 1), sum(sheets$records[!sheets$has_state & sheets$title_states == 1])))
cat(sprintf("period: %d sheets (%d records) have a year in the title but no period dimension (%d of them a range 'X to Y')\n",
            sum(!sheets$has_period & !is.na(sheets$title_period)), sum(sheets$records[!sheets$has_period & !is.na(sheets$title_period)]),
            sum(!sheets$has_period & !is.na(sheets$title_period) & sheets$title_period_range)))
cat(sprintf("period: %d sheets have no period anywhere (title or dimension)\n", sum(!sheets$has_period & is.na(sheets$title_period))))
cat(sprintf("court_level: %d sheets name a court level in the title but have no court_level dimension\n", sum(!sheets$has_court_level & !is.na(sheets$title_court))))
cat(sprintf("estimate_type: %d sheets say 'standard error' in the title but have no estimate_type dimension\n", sum(!sheets$has_estimate_type & sheets$title_se)))
cat(sprintf("stacked characteristic/category: %d sheets\n", sum(sheets$stacked)))
cat(sprintf("table-level meta_data dimensions not yet in records: %d tables\n", sum(sheets$tables_with_meta)))
print(sheets %>% filter(!has_state, title_states == 1) %>% count(publication_id))

cat("\n== examples of title constants\n")
ex <- sheets %>% filter((!has_state & title_states == 1) | (!has_period & !is.na(title_period)) | (!has_court_level & !is.na(title_court)) | (!has_estimate_type & title_se)) %>%
  group_by(publication_id) %>% slice_sample(n = 2) %>% ungroup()
for (k in seq_len(nrow(ex))) cat(sprintf("- [%s] %s\n    dims: %s\n", ex$publication_id[k], str_trunc(ex$title[k], 200), paste(ex$dims[[k]], collapse = ", ")))
