# Reference-independent checks over all data recipes.
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
source("R/expand_excel_range.R"); source("orchestrator/qa/recipe_labels.R")
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
rs <- readRDS("orchestrator/qa/cache/recipes.rds") %>% filter(kind == "data")
fmt_cache <- list()

rows <- list(); dims <- list(); dup <- list(); hier <- list(); nums <- list(); metas <- list()
for (i in seq_len(nrow(rs))) {
  r <- rs[i, ]
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  path <- file.path("source-spreadsheets-xlsx", r$xlsx_file)
  cells <- tidyxl::xlsx_cells(path, sheets = r$sheets)
  if (is.null(fmt_cache[[path]])) fmt_cache[[path]] <- tidyxl::xlsx_formats(path)
  f <- fmt_cache[[path]]
  cells <- cells %>% mutate(.value = coalesce(character, as.character(numeric), as.character(date), as.character(logical), error),
                            indent = coalesce(f$local$alignment$indent[local_format_id], 0L),
                            numfmt = f$local$numFmt[local_format_id])
  labs <- recipe_labels(spec, cells %>% select(row, col, address, .value))

  # 1. one value cell getting two labels for the same dimension
  d <- labs %>% count(address, table_name, dim) %>% filter(n > 1)
  if (nrow(d)) dup[[r$sheet_sha256]] <- d %>% mutate(sheet = r$sheets, sheet_sha256 = r$sheet_sha256, publication_id = r$publication_id)

  # 2. dimension names
  dims[[i]] <- tibble(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256,
                      dim = unique(c(map_chr(unlist(map(spec$tables, "headers"), recursive = FALSE), "name"),
                                     map_chr(unlist(map(spec$tables, ~ .x$meta_data %||% list()), recursive = FALSE), "name"))))
  metas[[i]] <- tibble(publication_id = r$publication_id, name = map_chr(spec$meta_data %||% list(), "name"))

  # 3. flattened hierarchies: a W row header whose label cells have more than one indent level
  for (t in spec$tables) for (h in t$headers) if (h$direction %in% c("W", "left")) {
    hc <- cells %>% filter(address %in% expand_excel_range(h$cells), !is.na(.value))
    lv <- sort(unique(hc$indent))
    leading <- any(str_detect(hc$.value, "^\\s{2,}"))
    if (length(lv) > 1 || leading) hier[[length(hier) + 1]] <- tibble(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256, sheet = r$sheets,
      table = t$name, header = h$name, indent_levels = paste(lv, collapse = ","), leading_spaces = leading,
      other_dims = paste(setdiff(c(map_chr(t$headers, "name"), map_chr(t$meta_data %||% list(), "name")), h$name), collapse = ","))
  }

  # 4. period: does any dimension name look like a period?
  period_dim <- any(str_detect(str_to_lower(unique(labs$dim)), "year|period|date|quarter|month"))
  period_in_labels <- any(str_detect(labs$label %||% "", "(19|20)[0-9]{2}"))

  # 5. stored vs displayed numbers: values whose stored decimals exceed the format's decimals
  vals <- cells %>% filter(address %in% unique(labs$address), !is.na(numeric))
  fmt_dec <- ifelse(str_detect(vals$numfmt %||% "", "\\."), nchar(str_extract(vals$numfmt, "(?<=\\.)0+")), 0L)
  fmt_dec[is.na(fmt_dec)] <- 0L
  general <- is.na(vals$numfmt) | vals$numfmt == "General"
  stored_dec <- nchar(str_extract(format(vals$numeric, digits = 15, scientific = FALSE, trim = TRUE), "(?<=\\.)[0-9]+$"))
  stored_dec[is.na(stored_dec)] <- 0L
  nums[[i]] <- tibble(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256, numeric_values = nrow(vals),
                      more_precise_than_shown = sum(!general & stored_dec > fmt_dec))

  rows[[i]] <- tibble(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256, sheet = r$sheets,
                      tables = length(spec$tables), period_dim = period_dim, period_in_labels = period_in_labels,
                      title_in_sheet_meta = any(map_chr(spec$meta_data %||% list(), "name") %in% c("table_title", "title")),
                      title_in_table_meta = any(map_lgl(spec$tables, ~ any(map_chr(.x$meta_data %||% list(), "name") %in% c("table_title", "title")))),
                      notes = any(str_detect(map_chr(spec$meta_data %||% list(), "name"), "note")))
}
rows <- bind_rows(rows); dims <- bind_rows(dims); dup <- bind_rows(dup); hier <- bind_rows(hier); nums <- bind_rows(nums); metas <- bind_rows(metas)
saveRDS(list(rows = rows, dims = dims, dup = dup, hier = hier, nums = nums, metas = metas), "orchestrator/qa/cache/corpus.rds")

cat("== 1. value cells with two labels for one dimension:", nrow(dup), "cells on", n_distinct(dup$sheet_sha256), "sheets\n")
if (nrow(dup)) print(dup %>% count(publication_id, sheet, sheet_sha256 = substr(sheet_sha256, 1, 8), table_name, dim) %>% head(10))
cat("\n== 2. distinct dimension names:", n_distinct(dims$dim), "| by publication:\n")
print(dims %>% group_by(publication_id) %>% summarise(sheets = n_distinct(sheet_sha256), distinct_dims = n_distinct(dim),
  examples = paste(head(names(sort(table(dim), decreasing = TRUE)), 12), collapse = " | ")), width = 250)
cat("\nPeriod-like names:", paste(sort(unique(dims$dim[str_detect(str_to_lower(dims$dim), "year|period")])), collapse = " | "), "\n")
cat("State-like names:", paste(sort(unique(dims$dim[str_detect(str_to_lower(dims$dim), "state|jurisdiction|territor")])), collapse = " | "), "\n")
cat("Measure-like names:", paste(sort(unique(dims$dim[str_detect(str_to_lower(dims$dim), "measure|unit|statistic|estimate|data")])), collapse = " | "), "\n")
cat("Sheet meta names:", paste(names(sort(table(metas$name), decreasing = TRUE)), collapse = " | "), "\n")
cat("\n== 3. W row headers mixing indent levels (flattened hierarchy):", nrow(hier), "headers in", n_distinct(hier$sheet_sha256), "of", nrow(rows), "sheets\n")
print(hier %>% count(publication_id))
cat("\n== 4. sheets with no period-like dimension:", sum(!rows$period_dim), "of", nrow(rows), "\n")
print(rows %>% group_by(publication_id) %>% summarise(sheets = n(), no_period_dim = sum(!period_dim), title_sheet = sum(title_in_sheet_meta), title_table = sum(title_in_table_meta), no_notes = sum(!notes)))
cat("\n== 5. numeric values stored with more decimals than displayed:", sum(nums$more_precise_than_shown), "of", sum(nums$numeric_values), "\n")
print(nums %>% group_by(publication_id) %>% summarise(values = sum(numeric_values), more_precise = sum(more_precise_than_shown), pct = round(100 * more_precise / values, 1)))
