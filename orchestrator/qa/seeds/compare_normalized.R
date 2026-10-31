# Compare every original workbook with its normalised copy, cell by cell.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
source("R/published_value.R")
manifest <- jsonlite::read_json("source-spreadsheets-xlsx/original-package-metadata/manifest.json")
files <- list.files("source-spreadsheets-xlsx", pattern = "\\.xlsx$")
by_sha <- setNames(files, substr(files, 1, 64))

read_book <- function(file) {
  path <- file.path("source-spreadsheets-xlsx", file)
  t <- system.time({
    cells <- tidyxl::xlsx_cells(path)
    fmt <- tidyxl::xlsx_formats(path)$local$numFmt
  })[["elapsed"]]
  list(seconds = t, all_cells = nrow(cells), sheets = tidyxl::xlsx_sheet_names(path),
       cells = cells %>% filter(!is_blank) %>%
         transmute(sheet, address, data_type,
                   value = coalesce(character, as.character(numeric), as.character(date), as.character(logical), error),
                   published = coalesce(character, published_value(numeric, fmt[local_format_id]), as.character(date), as.character(logical), error),
                   formula))
}

rows <- map_dfr(manifest$normalizationRelationships, function(r) {
  e <- r$entryAsRecorded
  src <- by_sha[[sub("sha256:", "", r$sourceSha256)]]; out <- by_sha[[sub("sha256:", "", r$outputSha256)]]
  a <- read_book(src); b <- read_book(out)
  common <- intersect(a$sheets, b$sheets)
  j <- full_join(a$cells %>% filter(sheet %in% common), b$cells %>% filter(sheet %in% common),
                 by = c("sheet", "address"), suffix = c("_src", "_out"))
  only_src <- j %>% filter(is.na(data_type_out)); only_out <- j %>% filter(is.na(data_type_src))
  both <- j %>% filter(!is.na(data_type_src), !is.na(data_type_out))
  changed <- both %>% filter(value_src != value_out | data_type_src != data_type_out)
  pub_changed <- both %>% filter(published_src != published_out)
  tibble(
    normalization = e$normalization, correction = e$correction$id %||% NA_character_,
    source_file = src, output_file = out,
    sheets_src = length(a$sheets), sheets_out = length(b$sheets),
    sheets_dropped = paste(setdiff(a$sheets, b$sheets), collapse = "; "),
    nonblank_src = nrow(a$cells %>% filter(sheet %in% common)), nonblank_out = nrow(b$cells %>% filter(sheet %in% common)),
    nonblank_in_dropped_sheets = nrow(a$cells %>% filter(!sheet %in% common)),
    cells_src = a$all_cells, cells_out = b$all_cells,
    removed = nrow(only_src), added = nrow(only_out), value_changed = nrow(changed), published_changed = nrow(pub_changed),
    formula_changed = sum(coalesce(both$formula_src, "") != coalesce(both$formula_out, "")),
    removed_examples = paste(head(paste0(only_src$sheet, "!", only_src$address, "=", str_trunc(only_src$value_src, 30)), 4), collapse = " | "),
    changed_examples = paste(head(paste0(changed$sheet, "!", changed$address, ": ", changed$value_src, " -> ", changed$value_out), 4), collapse = " | "),
    seconds_src = a$seconds, seconds_out = b$seconds)
})
saveRDS(rows, "orchestrator/qa/cache/normalized_pairs.rds")
cat("pairs:", nrow(rows), "\n")
print(rows %>% summarise(pairs = n(), sheets_dropped = sum(sheets_src - sheets_out), nonblank_src = sum(nonblank_src),
                         removed = sum(removed), added = sum(added), value_changed = sum(value_changed),
                         published_changed = sum(published_changed), formula_changed = sum(formula_changed),
                         nonblank_in_dropped_sheets = sum(nonblank_in_dropped_sheets)))
cat("\nall tidyxl cells (incl. styled blanks): source", sum(rows$cells_src), "-> normalised", sum(rows$cells_out),
    "| read time: source", round(sum(rows$seconds_src)), "s -> normalised", round(sum(rows$seconds_out)), "s\n")
print(rows %>% group_by(normalization) %>% summarise(pairs = n(), dropped_sheets = sum(sheets_src - sheets_out), removed = sum(removed), added = sum(added),
  value_changed = sum(value_changed), published_changed = sum(published_changed), cells_src = sum(cells_src), cells_out = sum(cells_out)), width = 200)
cat("\npairs with any removed/added/changed non-blank cell:\n")
print(as.data.frame(rows %>% filter(removed + added + value_changed + published_changed + formula_changed > 0) %>%
  transmute(output = str_trunc(sub("^[0-9a-f]{64}--", "", output_file), 50), removed, added, value_changed, published_changed, formula_changed,
            examples = str_trunc(paste(removed_examples, changed_examples), 160))), row.names = FALSE)
