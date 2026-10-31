# Fingerprint the non-blank content of every sheet in every workbook, to find duplicated sheets.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
files <- unique(m$xlsx_file)
fp <- map_dfr(files, function(f) {
  cells <- tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", f)) %>% filter(!is_blank) %>%
    mutate(value = coalesce(character, as.character(numeric), as.character(date), as.character(logical), error))
  # content inside column L... is irrelevant to the comparison only if it is a full-width artifact; keep everything
  cells %>% group_by(sheet) %>% arrange(row, col, .by_group = TRUE) %>%
    summarise(cells = n(), content = digest::digest(paste(address, value, sep = "=", collapse = "\n"), algo = "sha256", serialize = FALSE),
              # same content ignoring cells beyond column Z (the full-width artifacts)
              content_a_z = digest::digest(paste((address)[col <= 26], value[col <= 26], sep = "=", collapse = "\n"), algo = "sha256", serialize = FALSE),
              .groups = "drop") %>%
    mutate(xlsx_file = f)
})
x <- m %>% select(xlsx_file, sheets, sheet_sha256, publication_id, normalization, normalized_from_sha256, normalized_to_sha256) %>%
  left_join(fp, by = c("xlsx_file", "sheets" = "sheet"))
saveRDS(x, "orchestrator/qa/cache/sheet_fingerprints.rds")

cat("sheets:", nrow(x), "| empty sheets:", sum(is.na(x$cells)), "\n")
dups <- x %>% filter(!is.na(cells)) %>% group_by(content_a_z) %>% filter(n_distinct(xlsx_file) > 1) %>% ungroup()
cat("sheets whose content (columns A:Z) also appears in another workbook:", nrow(dups), "in", n_distinct(dups$content_a_z), "groups\n")
dups <- dups %>% mutate(role = case_when(!is.na(normalized_to_sha256) ~ "original with normalised copy",
                                         !is.na(normalized_from_sha256) ~ "normalised copy",
                                         TRUE ~ "other"))
print(count(dups, role))
cat("\nduplicate groups that are not original/normalised pairs:\n")
other <- dups %>% group_by(content_a_z) %>% filter(any(role == "other")) %>% ungroup()
print(as.data.frame(other %>% arrange(content_a_z) %>% transmute(group = substr(content_a_z, 1, 8), file = str_trunc(sub("^[0-9a-f]{64}--", "", xlsx_file), 62), sheets, cells, role)) %>% head(40), row.names = FALSE)
