# Compare each data recipe with the database's per-cell reference labels.
# For every value cell: which label cells the recipe attaches vs. the reference.
# ABS historical releases only (source_cell_observation has label cell addresses).
# Usage: Rscript orchestrator/qa/compare_reference.R <batch>   (after batch_recipes.R)
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(DBI); library(RSQLite)})
source("R/expand_excel_range.R")

m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c", sheet_index = "i"), trim_ws = FALSE)
name <- commandArgs(TRUE)[1]
recipes <- readRDS(sprintf("orchestrator/qa/cache/%s_recipes.rds", name)) %>% filter(kind == "data")
con <- dbConnect(SQLite(), "tidy-data-asset-status.sqlite3", flags = SQLITE_RO)

sheet_cells <- function(r) {
  tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", r$xlsx_file), sheets = r$sheets) %>%
    mutate(.value = coalesce(character, as.character(numeric), as.character(date), as.character(logical), error)) %>%
    select(row, col, address, .value, is_blank, numeric, character)
}

# One row per (value cell, attached label): label cell address and text
recipe_labels <- function(spec, cells) {
  map_dfr(seq_along(spec$tables), function(i) {
    t <- spec$tables[[i]]
    vals <- cells %>% filter(address %in% expand_excel_range(t$values_range)) %>% select(row, col, address, .value)
    tmeta <- map_dfr(t$meta_data %||% list(), function(md) {
      cells %>% filter(address %in% expand_excel_range(md$cells), !is.na(.value)) %>%
        transmute(dim = md$name, label_cell = address, label = .value)
    })
    from_meta <- tidyr::crossing(vals %>% select(address), tmeta)
    from_headers <- map_dfr(t$headers, function(h) {
      hc <- cells %>% filter(address %in% expand_excel_range(h$cells)) %>% transmute(row, col, label_cell = address, label = .value)
      out <- tryCatch(unpivotr::enhead(vals, hc, h$direction), error = function(e) NULL)
      if (is.null(out)) return(tibble())
      out %>% transmute(address, dim = h$name, label_cell, label)
    })
    bind_rows(from_meta, from_headers) %>% mutate(table = i, table_name = t$name)
  })
}

reference <- function(r) {
  q <- dbGetQuery(con, "
    SELECT source_cell AS address, raw_value_text, value_status, row_dimensions_json,
           json_extract(semantic_json, '$.column_heading_cells') AS col_cells,
           json_extract(semantic_json, '$.column_heading_path') AS col_path
    FROM source_cell_observation
    WHERE source_workbook_digest = ? AND source_sheet = ?",
    params = list(paste0("sha256:", r$source_sha256), r$sheets))
  if (!nrow(q)) return(NULL)
  q %>% mutate(
    ref_cells = map2(row_dimensions_json, col_cells, function(rd, cc) {
      rows <- if (is.na(rd)) character() else map_chr(jsonlite::fromJSON(rd, simplifyVector = FALSE), ~ .x$source_cell %||% NA_character_)
      cols <- if (is.na(cc)) character() else unlist(jsonlite::fromJSON(cc))
      unique(na.omit(c(rows, cols)))
    })
  )
}

recipes <- recipes %>% left_join(m %>% select(sheet_sha256, source_sha256), by = "sheet_sha256")
results <- list(); cell_rows <- list()
for (i in seq_len(nrow(recipes))) {
  r <- recipes[i, ]
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  ref <- reference(r)
  cells <- sheet_cells(r)
  sheet_meta_cells <- unlist(map(spec$meta_data %||% list(), ~ expand_excel_range(.x$cells)))
  labs <- recipe_labels(spec, cells)
  value_cells <- unique(unlist(map(spec$tables, ~ expand_excel_range(.x$values_range))))
  nonblank_values <- intersect(value_cells, cells$address[!is.na(cells$.value)])

  # label-value collisions: two value cells with identical labels (incl. table name)
  keys <- labs %>% group_by(address, table_name) %>% arrange(dim) %>%
    summarise(key = paste(dim, label, sep = "=", collapse = "|"), n_dup = n() - n_distinct(dim), .groups = "drop")
  collisions <- keys %>% group_by(key) %>% filter(n() > 1) %>% ungroup()
  collisions_ignoring_table <- labs %>% group_by(address) %>% arrange(dim) %>%
    summarise(key = paste(dim, label, sep = "=", collapse = "|"), .groups = "drop") %>% group_by(key) %>% filter(n() > 1) %>% ungroup()

  res <- tibble(sheet_sha256 = r$sheet_sha256, publication_id = r$publication_id, sheet = r$sheets, xlsx_file = r$xlsx_file,
                tables = length(spec$tables), value_cells = length(nonblank_values),
                multi_label_cells = sum(keys$n_dup > 0),
                colliding_cells = nrow(collisions), colliding_cells_ignoring_table = nrow(collisions_ignoring_table),
                has_reference = !is.null(ref))
  if (!is.null(ref)) {
    rec <- labs %>% group_by(address) %>% summarise(rec_cells = list(unique(label_cell)), .groups = "drop")
    cmp <- ref %>% select(address, ref_cells, raw_value_text, value_status) %>%
      inner_join(rec, by = "address") %>%
      mutate(missing = map2(ref_cells, rec_cells, setdiff), extra = map2(rec_cells, ref_cells, setdiff),
             missing_in_sheet_meta = map_lgl(missing, ~ length(.x) > 0 && all(.x %in% sheet_meta_cells)),
             n_missing = lengths(missing), n_extra = lengths(extra),
             outcome = case_when(n_missing == 0 & n_extra == 0 ~ "exact",
                                 n_missing > 0 & n_extra == 0 & missing_in_sheet_meta ~ "missing (label kept as sheet meta)",
                                 n_missing > 0 & n_extra == 0 ~ "missing labels",
                                 n_missing == 0 & n_extra > 0 ~ "extra labels",
                                 TRUE ~ "different labels"))
    res <- res %>% mutate(
      ref_cells_total = nrow(ref),
      ref_cells_not_in_recipe = length(setdiff(ref$address, nonblank_values)),
      recipe_cells_not_in_ref = length(setdiff(nonblank_values, ref$address)),
      compared = nrow(cmp),
      exact = sum(cmp$outcome == "exact"),
      missing_sheet_meta = sum(cmp$outcome == "missing (label kept as sheet meta)"),
      missing = sum(cmp$outcome == "missing labels"),
      extra = sum(cmp$outcome == "extra labels"),
      different = sum(cmp$outcome == "different labels"))
    cell_rows[[r$sheet_sha256]] <- cmp %>% mutate(sheet_sha256 = r$sheet_sha256) %>%
      select(sheet_sha256, address, outcome, missing, extra, raw_value_text, value_status)
    res$ref_not_in_recipe_examples <- list(head(setdiff(ref$address, nonblank_values), 8))
    res$recipe_not_in_ref_examples <- list(head(setdiff(nonblank_values, ref$address), 8))
  }
  results[[i]] <- res
}
dbDisconnect(con)
results <- bind_rows(results)
saveRDS(results, sprintf("orchestrator/qa/cache/compare_results_%s.rds", name))
saveRDS(bind_rows(cell_rows), sprintf("orchestrator/qa/cache/compare_cells_%s.rds", name))

cat("data recipes:", nrow(results), " with reference:", sum(results$has_reference), "\n")
w <- results %>% filter(has_reference)
cat(sprintf("value cells: recipe %d | reference %d | reference cells missed by recipe %d | recipe cells not in reference %d\n",
            sum(w$value_cells), sum(w$ref_cells_total), sum(w$ref_cells_not_in_recipe), sum(w$recipe_cells_not_in_ref)))
cat(sprintf("compared cells %d: exact %.1f%% | missing (kept as sheet meta) %.1f%% | missing labels %.1f%% | extra labels %.1f%% | different %.1f%%\n",
            sum(w$compared), 100 * sum(w$exact) / sum(w$compared), 100 * sum(w$missing_sheet_meta) / sum(w$compared),
            100 * sum(w$missing) / sum(w$compared), 100 * sum(w$extra) / sum(w$compared), 100 * sum(w$different) / sum(w$compared)))
cat("cells with label collisions (incl. table name):", sum(results$colliding_cells), " ignoring table name:", sum(results$colliding_cells_ignoring_table),
    " cells with two labels for one dimension:", sum(results$multi_label_cells), "\n")
print(w %>% group_by(publication_id) %>% summarise(sheets = n(), compared = sum(compared), exact = round(100 * sum(exact) / sum(compared), 1),
  sheet_meta = round(100 * sum(missing_sheet_meta) / sum(compared), 1), missing = round(100 * sum(missing) / sum(compared), 1),
  extra = round(100 * sum(extra) / sum(compared), 1), different = round(100 * sum(different) / sum(compared), 1),
  ref_missed = sum(ref_cells_not_in_recipe), not_in_ref = sum(recipe_cells_not_in_ref)), width = 200)
