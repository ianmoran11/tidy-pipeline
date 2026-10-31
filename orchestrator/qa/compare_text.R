# Text-level comparison of recipe labels with the database reference: for AIHW, RoGS and EEH, whose
# reference labels are text without cell addresses. Run inventory.R first.
# Usage: Rscript orchestrator/qa/compare_text.R [publication_id regex]
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(DBI); library(RSQLite)})
source("R/expand_excel_range.R")
source("orchestrator/qa/recipe_labels.R")   # sheet_cells(), recipe_labels()

m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c", sheet_index = "i"), trim_ws = FALSE)
pubs <- commandArgs(TRUE)[1] %||% "."
recipes <- readRDS("orchestrator/qa/cache/recipes.rds") %>% filter(kind == "data", str_detect(publication_id, pubs)) %>%
  left_join(m %>% select(sheet_sha256, source_sha256), by = "sheet_sha256")
con <- dbConnect(SQLite(), "tidy-data-asset-status.sqlite3", flags = SQLITE_RO)

norm <- function(x) x %>% str_replace_all("[\u2013\u2014\u2212]", "-") %>% str_replace_all("_", " ") %>%
  str_to_lower() %>% str_remove_all("\\s*\\((?:[a-z]{1,2}|[0-9]{1,2})\\)") %>% str_remove("[*]+$") %>% str_squish()

r1c1_to_a1 <- function(x) {
  is_r1c1 <- str_detect(x, "^R[0-9]+C[0-9]+$")
  x[is_r1c1] <- paste0(cellranger::num_to_letter(as.integer(str_match(x[is_r1c1], "C([0-9]+)$")[, 2])),
                       str_match(x[is_r1c1], "^R([0-9]+)")[, 2])
  x
}

ref_text <- function(r) {
  q <- dbGetQuery(con, "
    SELECT source_cell AS address, row_group, row_label, row_dimensions_json, column_heading_json,
           statistic_basis, estimate_type, json_extract(semantic_json, '$.column_heading_path') AS col_path
    FROM source_cell_observation WHERE source_workbook_digest = ? AND source_sheet = ?",
    params = list(paste0("sha256:", r$source_sha256), r$sheets))
  if (!nrow(q)) return(NULL)
  q %>% mutate(
    address = r1c1_to_a1(address),
    ref = pmap(list(row_group, row_label, row_dimensions_json, column_heading_json, col_path, statistic_basis),
      function(rg, rl, rd, ch, cp, sb) {
        dims <- if (is.na(rd)) character() else map_chr(jsonlite::fromJSON(rd, simplifyVector = FALSE), ~ as.character(.x$label %||% .x$value %||% NA))
        heads <- c(if (!is.na(ch)) unlist(jsonlite::fromJSON(ch)), if (!is.na(cp)) unlist(jsonlite::fromJSON(cp)))
        atoms <- unlist(str_split(c(rg, rl, dims, heads, sb), " \\| | / "))
        unique(na.omit(norm(atoms)))
      })) %>% select(address, ref)
}

out <- list(); examples <- list()
for (i in seq_len(nrow(recipes))) {
  r <- recipes[i, ]
  ref <- ref_text(r)
  if (is.null(ref)) next
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  labs <- recipe_labels(spec, sheet_cells(r)) %>% filter(!is.na(label)) %>% mutate(n = norm(label))
  rec <- labs %>% group_by(address) %>% summarise(rec = list(unique(n)), names = list(unique(norm(dim))), .groups = "drop")
  sheet_meta_text <- norm(unlist(map(spec$meta_data %||% list(), function(md) { cs <- sheet_cells(r); cs$.value[cs$address %in% expand_excel_range(md$cells)] })))
  cmp <- inner_join(ref, rec, by = "address")
  if (!nrow(cmp)) next
  # labels attached to every compared cell are sheet-level context (title, units), not dimensions
  constant <- Reduce(intersect, cmp$rec)
  cmp <- cmp %>% mutate(
    missing_all = map2(ref, rec, setdiff),
    missing = map2(missing_all, names, setdiff),
    missing_sheet_meta = map_lgl(missing, ~ length(.x) > 0 && all(.x %in% sheet_meta_text)),
    extra = map2(rec, ref, ~ setdiff(setdiff(.x, .y), constant)),
    outcome = case_when(lengths(missing) == 0 & lengths(extra) == 0 ~ "match",
                        missing_sheet_meta & lengths(extra) == 0 ~ "missing (kept as sheet meta)",
                        lengths(missing) > 0 & lengths(extra) == 0 ~ "missing",
                        lengths(missing) == 0 & lengths(extra) > 0 ~ "extra",
                        TRUE ~ "different"))
  out[[i]] <- tibble(sheet_sha256 = r$sheet_sha256, publication_id = r$publication_id, sheet = r$sheets,
                     compared = nrow(cmp), match = sum(cmp$outcome == "match"), sheet_meta = sum(cmp$outcome == "missing (kept as sheet meta)"), missing = sum(cmp$outcome == "missing"),
                     extra = sum(cmp$outcome == "extra"), different = sum(cmp$outcome == "different"),
                     constant_labels = paste(str_trunc(constant, 50), collapse = " ; "))
  examples[[r$sheet_sha256]] <- cmp %>% filter(outcome != "match") %>% mutate(sheet_sha256 = r$sheet_sha256, sheet = r$sheets, publication_id = r$publication_id)
}
dbDisconnect(con)
out <- bind_rows(out); ex <- bind_rows(examples)
saveRDS(out, "orchestrator/qa/cache/text_results2.rds"); saveRDS(ex, "orchestrator/qa/cache/text_examples2.rds")
cat(sprintf("compared cells %d on %d sheets: match %.1f%% | missing %.1f%% | extra %.1f%% | different %.1f%%\n",
            sum(out$compared), nrow(out), 100 * sum(out$match) / sum(out$compared), 100 * sum(out$missing) / sum(out$compared),
            100 * sum(out$extra) / sum(out$compared), 100 * sum(out$different) / sum(out$compared)))
print(out %>% group_by(publication_id) %>% summarise(sheets = n(), compared = sum(compared),
  match = round(100 * sum(match) / sum(compared), 1), sheet_meta = round(100 * sum(sheet_meta) / sum(compared), 1), missing = round(100 * sum(missing) / sum(compared), 1),
  extra = round(100 * sum(extra) / sum(compared), 1), different = round(100 * sum(different) / sum(compared), 1),
  sheets_all_match = sum(match == compared)), width = 200)
cat("\nMost common missing / extra label texts by publication:\n")
ex %>% select(publication_id, missing) %>% unnest(missing) %>% count(publication_id, missing, sort = TRUE) %>%
  group_by(publication_id) %>% slice_head(n = 4) %>% print(n = 40, width = 200)
ex %>% select(publication_id, extra) %>% unnest(extra) %>% count(publication_id, extra, sort = TRUE) %>%
  group_by(publication_id) %>% slice_head(n = 4) %>% print(n = 40, width = 200)
