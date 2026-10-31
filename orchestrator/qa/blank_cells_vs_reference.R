# Blank-cell records (value_status "blank") vs the blank cells the reference database
# records, on a sample of historical ABS sheets (source_cell_observation has cell
# addresses). Precision: our blanks the database also has. Recall: database blanks we
# have. The misses are mostly rows or columns that are blank throughout, which recipes
# leave out of their tables (ISSUES.md I5). EEH is excluded: the database doesn't
# record EEH blanks.
# Usage: Rscript orchestrator/qa/blank_cells_vs_reference.R [n_sheets]
suppressMessages({library(dplyr); library(purrr); library(stringr); library(DBI); library(RSQLite)})
n <- as.integer(commandArgs(TRUE)[1] %||% 250)
obs <- targets::tar_read(observations); src <- targets::tar_read(integrated)$sources
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
cand <- src %>% filter(!is.na(release_date), publisher == "Australian Bureau of Statistics", publication_id != "employee-earnings-hours-australia") %>%
  left_join(m %>% select(sheet_sha256, source_sha256), by = "sheet_sha256")
set.seed(7); cand <- cand %>% slice_sample(n = min(n, nrow(cand)))
con <- dbConnect(SQLite(), "tidy-data-asset-status.sqlite3", flags = SQLITE_RO)
res <- map_dfr(seq_len(nrow(cand)), function(i) {
  r <- cand[i, ]
  db <- dbGetQuery(con, "SELECT source_cell AS address, value_status FROM source_cell_observation WHERE source_workbook_digest = ? AND source_sheet = ?",
                   params = list(paste0("sha256:", r$source_sha256), r$sheet))
  if (!nrow(db)) return(NULL)
  cells <- tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", r$xlsx_file), sheets = r$sheet)
  d <- db$address[!db$address %in% cells$address[!cells$is_blank]]
  o <- obs$address[obs$sheet_sha256 == r$sheet_sha256 & obs$value_status == "blank"]
  tibble(publication_id = r$publication_id, ours = length(o), db = length(d), both = length(intersect(o, d)))
})
dbDisconnect(con)
cat("sheets with reference:", nrow(res), "\n")
print(res %>% group_by(publication_id) %>% summarise(sheets = n(), ours = sum(ours), db = sum(db), both = sum(both),
  precision = round(both / ours, 3), recall = round(both / db, 3)))
