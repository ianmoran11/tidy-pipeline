# Adds workbook-level symbol meanings to integration/value_spec.json from each
# workbook's own legend ("na = not applicable", "na Not available."). An entry is
# written only where the legend differs from the meaning the spec would otherwise use
# (the publication's, then "default"). Workbooks whose legends give both meanings get
# no entry and are listed. Rerun after preparing new workbooks; existing workbook
# entries are replaced.
# Also adds two ABS legend symbols seen in older releases: "-" (nil or rounded to zero)
# and ". ." (not applicable).
suppressMessages({library(dplyr); library(purrr); library(stringr)})
spec_path <- "integration/value_spec.json"
spec <- jsonlite::read_json(spec_path)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c"), na = c("", "NA"), trim_ws = FALSE, show_col_types = FALSE)
books <- m %>% filter(reference_only == "FALSE") %>% distinct(publication_id, xlsx_file)

legend <- "^\\s*(na|n\\.a\\.)\\s*(=|\\s)\\s*not (applicable|available)"
found <- map_dfr(seq_len(nrow(books)), function(i) {
  text <- tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", books$xlsx_file[i]))$character
  hit <- str_match(str_to_lower(text[!is.na(text)]), legend)
  hit <- unique(hit[!is.na(hit[, 1]), c(2, 4), drop = FALSE])
  if (!nrow(hit)) return(NULL)
  tibble(publication_id = books$publication_id[i], xlsx_file = books$xlsx_file[i], symbol = hit[, 1], status = paste0("not_", hit[, 2]))
})
mixed <- found %>% group_by(xlsx_file, symbol) %>% filter(n_distinct(status) > 1) %>% ungroup()
usual <- function(pub, symbol) (spec$symbols[[pub]][[symbol]] %||% spec$symbols$default[[symbol]])[["status"]] %||% NA_character_
overrides <- found %>% anti_join(mixed, by = c("xlsx_file", "symbol")) %>% distinct() %>%
  filter(status != map2_chr(publication_id, symbol, usual))

spec$symbols <- spec$symbols[!names(spec$symbols) %in% books$xlsx_file]   # replace earlier workbook entries
spec$symbols$default[["-"]] <- list(status = "nil_or_rounded_to_zero", value = 0)
spec$symbols$default[[". ."]] <- list(status = "not_applicable")
for (f in unique(overrides$xlsx_file)) {
  o <- overrides[overrides$xlsx_file == f, ]
  spec$symbols[[f]] <- setNames(lapply(o$status, function(s) list(status = s)), o$symbol)
}
jsonlite::write_json(spec, spec_path, auto_unbox = TRUE, pretty = TRUE)
cat("workbooks with an na legend:", n_distinct(found$xlsx_file), "| overrides written:", n_distinct(overrides$xlsx_file),
    "| workbooks with both meanings (no entry):", n_distinct(mixed$xlsx_file), "\n")
print(overrides %>% count(publication_id, symbol, status))
if (nrow(mixed)) cat("both meanings:", unique(mixed$xlsx_file), sep = "\n  ")
