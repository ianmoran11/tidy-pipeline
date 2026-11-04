# Unit tests for R/published_value.R, then published vs stored text on real value cells.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
source("R/expand_excel_range.R"); source("R/published_value.R")

cat("== unit tests\n")
t <- tibble::tribble(~x, ~fmt, ~want,
  2.675, "0.00", "2.68",            # binary 2.67499999... ; Excel shows 2.68
  2.5, "0", "3", -2.5, "0", "-3",   # half away from zero (R round() gives 2)
  0.15, "0.0", "0.2",               # binary 0.1499999...
  8425.26220429811, "#;##0", "8425",
  2.37887238760836, "0.0", "2.4",
  -9.45, "0.0_ ;-0.0", "-9.5",
  1234.5678, '_-* #,##0_-;-* #,##0_-;_-* "-"??_-;_-@_-', "1235",
  100000, "#,##0", "100000",        # as.character() gives "1e+05"
  0.0006, "0.000", "0.001",
  19.3, "General", "19.3",
  1011.7, "#;##0.00", "1011.7",     # tidyxl's broken built-in 4 (#,##0.00)
  0, "#;##0", "0",                  # built-in 3 (#,##0) shows zero as 0
  1e6, "General", "1000000",
  -0.204, "0.0%", "-20.4",          # percentages: the fraction times 100
  0.5, "0%", "50",
  0.12345, "0.00%", "12.35",
  0.0006, "0.0%", "0.1",
  -0.0349, "0.0%;-0.0%", "-3.5",
  0.15, '0.0"%"', "0.2")            # a quoted % is text, not a percentage
t$got <- map2_chr(t$x, t$fmt, published_value)
print(t %>% mutate(ok = got == want), n = 20)

cat("\n== all value cells in a sample of 200 data recipes (run inventory.R first)\n")
set.seed(1)
rs <- readRDS("orchestrator/qa/cache/recipes.rds") %>% filter(kind == "data") %>% slice_sample(n = 200)
fc <- list()
x <- map_dfr(seq_len(nrow(rs)), function(i) {
  r <- rs[i, ]; path <- file.path("source-spreadsheets-xlsx", r$xlsx_file)
  if (is.null(fc[[path]])) fc[[path]] <<- tidyxl::xlsx_formats(path)
  spec <- jsonlite::read_json(file.path("tidy-recipes", paste0(r$sheet_sha256, ".json")), simplifyVector = FALSE)
  vals <- unique(unlist(map(spec$tables, ~ expand_excel_range(.x$values_range))))
  tidyxl::xlsx_cells(path, sheets = r$sheets) %>% filter(address %in% vals, !is.na(numeric)) %>%
    transmute(publication_id = r$publication_id, sheet = r$sheets, address, numeric, numfmt = fc[[path]]$local$numFmt[local_format_id])
})
x <- x %>% mutate(current = as.character(numeric), published = published_value(numeric, numfmt))
cat("numeric values:", nrow(x), "\n")
cat("current pipeline text in scientific notation:", sum(str_detect(x$current, "e")), " e.g.", paste(head(unique(x$current[str_detect(x$current, "e")]), 5), collapse = ", "), "\n")
cat("published differs from current pipeline value:", sum(x$published != x$current), "\n")
print(x %>% filter(published != current) %>% group_by(publication_id) %>% summarise(n = n(), example = paste(first(current), "->", first(published), "(", first(numfmt), ")")))
cat("\nzeros under formats that display zero as blank or '-':",
    sum(x$numeric == 0 & str_detect(fix_numfmt(x$numfmt), '"-"')), "\n")
cat("published text in scientific notation:", sum(str_detect(x$published, "e")), "| NA:", sum(is.na(x$published)), "\n")
