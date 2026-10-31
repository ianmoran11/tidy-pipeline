# Build source-spreadsheets-xlsx/reference-only/reference-only.csv: the redundant
# copies to archive, the active workbook each duplicates, and how they differ.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
B <- "source-spreadsheets-xlsx"
files <- list.files(B, pattern = "^[0-9a-f]{64}--.*\\.xlsx$")
by_sha <- setNames(files, substr(files, 1, 64))
man <- jsonlite::read_json(file.path(B, "original-package-metadata/manifest.json"))
refs <- readr::read_csv(file.path(B, "original-package-metadata/database-references.csv"), show_col_types = FALSE, col_types = readr::cols(.default = "c")) %>%
  mutate(sha = sub("sha256:", "", sha256))
ref_text <- function(sha) {
  x <- refs %>% filter(sha == !!sha) %>% count(t = paste0(database_table, if_else(is.na(role), "", paste0("/", role))))
  if (nrow(x)) paste0(x$t, ": ", x$n, collapse = "; ") else "none"
}
pairs <- readRDS("orchestrator/qa/cache/normalized_pairs.rds")

copies <- map_dfr(man$normalizationRelationships, function(r) {
  e <- r$entryAsRecorded
  src <- sub("sha256:", "", r$sourceSha256); out <- sub("sha256:", "", r$outputSha256)
  p <- pairs %>% filter(output_file == by_sha[[out]])
  diff <- c(
    if (p$removed > 1000) paste0("removed ", format(p$removed, big.mark = ","), " junk cells: text repeated along a row out to column XFD"),
    if (p$removed > 0 && p$removed <= 1000) paste0("removed ", p$removed, " stray cell(s): ", p$removed_examples),
    if (p$value_changed > 0) paste0("changed ", p$changed_examples),
    if (!is.null(e$correction$reason)) paste0("recorded correction: ", e$correction$reason))
  tibble(xlsx_file = by_sha[[out]], source_sha256 = out, copy_type = "normalised copy", normalization = e$normalization,
         active_xlsx_file = by_sha[[src]], active_sha256 = src,
         differences = if (length(diff)) str_flatten(diff, " | ") else "same non-blank cells and values; only formatting differs",
         database_references = ref_text(out))
})

archive_dups <- c("criminal-courts-australia-2009-10-cube-9", "criminal-courts-australia-2012-13-cube-1", "criminal-courts-australia-2012-13-cube-6")
archives <- map_dfr(archive_dups, function(stem) {
  arch <- files[str_detect(files, fixed(paste0("--", stem, "-archive-member.xlsx")))]
  act <- files[str_detect(files, fixed(paste0("--", stem, "-source.xlsx")))]
  stopifnot(length(arch) == 1, length(act) == 1)
  tibble(xlsx_file = arch, source_sha256 = substr(arch, 1, 64), copy_type = "archive duplicate", normalization = NA_character_,
         active_xlsx_file = act, active_sha256 = substr(act, 1, 64),
         differences = "identical sheets and values; copy taken from the publisher's combined archive",
         database_references = ref_text(substr(arch, 1, 64)))
})

out <- bind_rows(copies, archives) %>% arrange(copy_type, xlsx_file)
stopifnot(!anyDuplicated(out$xlsx_file), all(out$active_xlsx_file %in% files), !any(out$active_xlsx_file %in% out$xlsx_file))
dir.create(file.path(B, "reference-only"), showWarnings = FALSE)
readr::write_csv(out, file.path(B, "reference-only/reference-only.csv"), na = "")
writeLines(out$xlsx_file, "orchestrator/qa/cache/archive_files.txt")
cat(nrow(out), "files:", sum(out$copy_type == "normalised copy"), "normalised copies,", sum(out$copy_type == "archive duplicate"), "archive duplicates\n")
print(count(out, differences = str_trunc(differences, 90), sort = TRUE), n = 15)
