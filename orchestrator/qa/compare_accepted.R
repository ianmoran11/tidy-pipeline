# Compare batch recipes with the database's accepted observations for the same cells (sampled).
# Accepted (2020+) releases only. Usage: Rscript orchestrator/qa/compare_accepted.R agents/<batch>.txt   (after batch_recipes.R)
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(DBI); library(RSQLite)})
source("R/expand_excel_range.R"); source("R/published_value.R")
set.seed(42)
SAMPLE <- 120
args <- commandArgs(TRUE)
name <- tools::file_path_sans_ext(basename(args[1]))   # batch name, e.g. batch-abs-rest
batch <- readLines(args[1])
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
recs <- readRDS(sprintf("orchestrator/qa/cache/%s_recipes.rds", name)) %>% filter(kind == "data") %>% select(sheet_sha256) %>%
  left_join(m %>% select(sheet_sha256, sheets, xlsx_file, xlsx_path, source_sha256, publication_id), by = "sheet_sha256")
con <- dbConnect(SQLite(), "tidy-data-asset-status.sqlite3", flags = SQLITE_RO)
norm <- function(x) x %>% str_replace_all("[–—−]", "-") %>% str_to_lower() %>% str_remove_all("\\s*\\((?:[a-z]{1,2}|[0-9]{1,2})\\)") %>% str_squish()
a1 <- function(x) ifelse(str_detect(x, "^R[0-9]+C[0-9]+$"),
                         paste0(cellranger::num_to_letter(as.integer(str_match(x, "C([0-9]+)$")[, 2])), str_match(x, "^R([0-9]+)")[, 2]), x)

labels_for <- function(spec, cells) {
  map_dfr(spec$tables, function(t) {
    vals <- cells %>% filter(address %in% expand_excel_range(t$values_range)) %>% select(row, col, address, value)
    meta <- map_dfr(t$meta_data %||% list(), ~ cells %>% filter(address %in% expand_excel_range(.x$cells), !is.na(value)) %>% transmute(label = value))
    bind_rows(
      tidyr::crossing(vals %>% select(address), meta),
      map_dfr(t$headers, function(h) {
        hc <- cells %>% filter(address %in% expand_excel_range(h$cells)) %>% transmute(row, col, label = value)
        tryCatch(unpivotr::enhead(vals, hc, h$direction) %>% select(address, label), error = function(e) tibble())
      }))
  })
}

out <- list(); field_miss <- list(); bad_values <- list()
for (i in seq_len(nrow(recs))) {
  r <- recs[i, ]
  digests <- paste0("sha256:", c(r$source_sha256, m$source_sha256[m$active_sha256 %in% r$source_sha256]))
  assets <- dbGetQuery(con, sprintf("SELECT asset_id FROM asset WHERE sheet = ? AND source_digest IN (%s)", paste(rep("?", length(unique(digests))), collapse = ",")),
                       params = c(list(r$sheets), as.list(unique(digests))))$asset_id
  if (!length(assets)) next
  obs <- dbGetQuery(con, sprintf("SELECT source_cell, canonical_json FROM observation WHERE asset_id IN (%s)", paste(rep("?", length(assets)), collapse = ",")), params = as.list(assets))
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  path <- r$xlsx_path; fmt <- tidyxl::xlsx_formats(path)$local$numFmt
  cells <- tidyxl::xlsx_cells(path, sheets = r$sheets) %>%
    mutate(value = coalesce(character, published_value(numeric, fmt[local_format_id]), as.character(date), as.character(logical)))
  values <- unique(unlist(map(spec$tables, ~ expand_excel_range(.x$values_range))))
  values <- intersect(values, cells$address[!is.na(cells$value)])
  obs$address <- a1(obs$source_cell)
  common <- intersect(obs$address, values)
  samp <- obs %>% filter(address %in% common) %>% slice_sample(n = min(SAMPLE, length(common)))
  labs <- labels_for(spec, cells %>% select(row, col, address, value)) %>% filter(address %in% samp$address, !is.na(label)) %>%
    group_by(address) %>% summarise(rec = list(unique(norm(label))), .groups = "drop")
  ref <- samp %>% mutate(j = map(canonical_json, jsonlite::fromJSON, simplifyVector = FALSE),
                         raw = map(j, function(x) { f <- x[str_starts(names(x), "raw_") & !names(x) %in% c("raw_value", "raw_value_text", "raw_lexeme", "raw_semantic_scalar")]; f[!map_lgl(f, is.null)] }),
                         ref_value = map_dbl(j, ~ suppressWarnings(as.numeric(.x$raw_value %||% NA)))) %>% select(address, raw, ref_value)
  meta_text <- norm(c(unlist(map(spec$meta_data %||% list(), function(md) cells$value[cells$address %in% expand_excel_range(md$cells)])),
                      unlist(map(spec$tables, function(t) c(map_chr(t$headers, ~ .x$caption %||% NA_character_),
                                                             map_chr(t$meta_data %||% list(), ~ .x$caption %||% NA_character_))))))
  meta_text <- meta_text[!is.na(meta_text)]
  in_meta <- function(v) any(meta_text == v) || any(str_detect(meta_text, fixed(v)))
  cmp <- ref %>% inner_join(labs, by = "address") %>% left_join(cells %>% select(address, value), by = "address") %>%
    mutate(missing = map2(raw, rec, function(rw, rc) names(rw)[!norm(unlist(rw)) %in% rc]),
           where = map2(raw, missing, function(rw, ms) map_chr(ms, function(f) if (in_meta(norm(rw[[f]]))) "in title or sheet metadata only" else "not in recipe")),
           value_ok = is.na(ref_value) | abs(suppressWarnings(as.numeric(value)) - ref_value) < 1e-6 * pmax(1, abs(ref_value)))
  field_miss[[i]] <- cmp %>% select(missing, where) %>% unnest(c(missing, where)) %>% count(field = missing, where) %>% mutate(publication_id = r$publication_id, sheet_sha256 = r$sheet_sha256)
  bad_values[[i]] <- cmp %>% filter(!value_ok) %>% transmute(publication_id = r$publication_id, sheet = r$sheets, sheet_sha256 = r$sheet_sha256, address, recipe = value, reference = ref_value)
  out[[i]] <- tibble(publication_id = r$publication_id, sheet = r$sheets, sheet_sha256 = r$sheet_sha256,
                     n_obs = nrow(obs), recipe_values = length(values),
                     obs_not_in_recipe = length(setdiff(obs$address, values)), recipe_not_in_obs = length(setdiff(values, obs$address)),
                     sampled = nrow(cmp), all_labels_found = sum(lengths(cmp$missing) == 0),
                     all_found_or_in_meta = sum(map_lgl(cmp$where, ~ all(.x != "not in recipe"))), values_match = sum(cmp$value_ok, na.rm = TRUE))
}
dbDisconnect(con)
res <- bind_rows(out); fm <- bind_rows(field_miss)
bv <- bind_rows(bad_values)
saveRDS(list(res = res, fm = fm, bv = bv), sprintf("orchestrator/qa/cache/accepted_compare_%s.rds", name))
cat("data recipes in batch:", nrow(recs), "| with accepted observations:", nrow(res), "\n")
print(res %>% group_by(publication_id) %>% summarise(sheets = n(), obs = sum(n_obs), recipe_values = sum(recipe_values),
  obs_not_in_recipe = sum(obs_not_in_recipe), recipe_not_in_obs = sum(recipe_not_in_obs), sampled = sum(sampled),
  labels_found_pct = round(100 * sum(all_labels_found) / sum(sampled), 1), found_or_in_meta_pct = round(100 * sum(all_found_or_in_meta) / sum(sampled), 1), values_match_pct = round(100 * sum(values_match) / sum(sampled), 1)), width = 200)
cat("\nreference fields not found among the recipe's labels (sampled cells):\n")
print(fm %>% group_by(publication_id, field, where) %>% summarise(n = sum(n), sheets = n_distinct(sheet_sha256), .groups = "drop") %>% arrange(where, desc(n)), n = 30)
