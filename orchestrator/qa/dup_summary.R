suppressMessages({library(dplyr); library(purrr); library(stringr)})
x <- readRDS("orchestrator/qa/cache/sheet_fingerprints.rds") %>% filter(!is.na(cells))
short <- function(f) sub("^[0-9a-f]{64}--", "", f)
man <- jsonlite::read_json("source-spreadsheets-xlsx/original-package-metadata/manifest.json")
rel <- map_dfr(man$normalizationRelationships, ~ tibble(s = sub("sha256:", "", .x$sourceSha256), o = sub("sha256:", "", .x$outputSha256)))
recorded <- function(a, b) paste(substr(a, 1, 64), substr(b, 1, 64)) %in% c(paste(rel$s, rel$o), paste(rel$o, rel$s))
# numeric cells per sheet, to tell data sheets from boilerplate
num <- map_dfr(unique(x$xlsx_file), function(f) tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", f)) %>% filter(!is.na(numeric)) %>% count(sheet, name = "numeric_cells") %>% mutate(xlsx_file = f))
x <- x %>% left_join(num, by = c("xlsx_file", "sheets" = "sheet")) %>% mutate(numeric_cells = coalesce(numeric_cells, 0L))
sheets_per_book <- x %>% count(xlsx_file, name = "n")
p <- x %>% select(content_a_z, a = xlsx_file, numeric_cells) %>% inner_join(x %>% select(content_a_z, b = xlsx_file), by = "content_a_z", relationship = "many-to-many") %>%
  filter(a < b) %>% group_by(a, b) %>% summarise(shared = n(), shared_data_sheets = sum(numeric_cells > 0), .groups = "drop") %>%
  left_join(sheets_per_book %>% rename(a = xlsx_file, a_sheets = n), by = "a") %>% left_join(sheets_per_book %>% rename(b = xlsx_file, b_sheets = n), by = "b") %>%
  mutate(recorded = recorded(a, b),
         kind = case_when(recorded ~ "recorded original/normalised pair",
                          shared == pmin(a_sheets, b_sheets) & shared_data_sheets > 0 ~ "unrecorded: every sheet of one workbook duplicated",
                          shared_data_sheets > 0 ~ "unrecorded: some data sheets duplicated",
                          TRUE ~ "only non-data sheets shared (contents, notes)"))
print(p %>% count(kind, name = "workbook_pairs"))
cat("\nunrecorded duplicates of data sheets:\n")
print(as.data.frame(p %>% filter(str_starts(kind, "unrecorded")) %>% transmute(a = str_trunc(short(a), 60), b = str_trunc(short(b), 60), shared, data = shared_data_sheets, a_sheets, b_sheets)), row.names = FALSE)
saveRDS(p, "orchestrator/qa/cache/workbook_pairs.rds")
