# Review of newly admitted releases that the reference database doesn't cover: pipeline
# check warnings on their sheets, spec gaps (subjects, symbols, dates, labels), values
# that can't be told apart, and agreement with other releases where a new value repeats
# another release's series and period. Run after tar_make().
# Usage: Rscript orchestrator/qa/review_new_releases.R agents/<batch>.txt [agents/<batch>.txt ...]
suppressMessages({library(dplyr); library(stringr)})
options(width = 220)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c"), na = c("", "NA"), trim_ws = FALSE, show_col_types = FALSE)
new <- m$sheet_sha256[m$xlsx_file %in% unlist(lapply(commandArgs(TRUE), readLines))]
f <- targets::tar_read(check_failures)
cat("sheets in batch:", length(new), "| error-level failures (all sheets):", sum(f$severity == "error"), "\n\n== check warnings on these sheets\n")
print(as.data.frame(f %>% filter(sheet_sha256 %in% new) %>% group_by(target, test) %>%
  summarise(sheets = n(), failures = sum(n_failed), e.g. = str_trunc(first(examples), 90), .groups = "drop")), row.names = FALSE)

o <- targets::tar_read(observations); it <- targets::tar_read(integrated); src <- it$sources
no <- o %>% filter(sheet_sha256 %in% new); ns <- it$series %>% filter(series_id %in% no$series_id)
cat("\nobservations:", nrow(no), "| sheets with data:", n_distinct(no$sheet_sha256), "\nstatuses:", paste(names(table(no$value_status)), table(no$value_status), collapse = ", "), "\n")
cat("series:", nrow(ns), "| without population:", sum(is.na(ns$population)), "| without measure:", sum(is.na(ns$measure)), "\n")
cat("\n== unrecognised value text\n"); print(no %>% filter(value_status == "unrecognised") %>% count(published_text, sort = TRUE) %>% head(10))
cat("\n== subjects missing from measures/measure_spec.json\n")
print(as.data.frame(f %>% filter(test == "subject_in_spec", sheet_sha256 %in% new) %>% left_join(src %>% select(sheet_sha256, publication_id), by = "sheet_sha256") %>%
  mutate(subject = str_match(examples, "subject '(.*)' is not")[, 2]) %>% count(publication_id, subject, sort = TRUE)), row.names = FALSE)
cat("\n== measure labels naming a court level (candidates for split entries)\n")
print(ns %>% filter(str_detect(str_to_lower(measure), "court")) %>% count(publication_id, measure, court_level, sort = TRUE) %>% head(15))

cf <- targets::tar_read(integration_gaps)$conflicts %>% filter(numbers > 1)
nc <- o %>% semi_join(cf, by = c("release_id", "series_id", "period")) %>% semi_join(no %>% distinct(release_id, series_id, period), by = c("release_id", "series_id", "period"))
cat("\nvalues that can't be told apart involving these sheets:", n_distinct(paste(nc$release_id, nc$series_id, nc$period)), "keys,", nrow(nc), "cells\n")
tp <- nc %>% left_join(src %>% select(sheet_sha256, title), by = "sheet_sha256") %>% group_by(release_id, series_id, period) %>%
  summarise(t = paste(sort(unique(str_trunc(title, 80))), collapse = "  <>  "), .groups = "drop") %>% count(t, sort = TRUE) %>% head(8)
cat(sprintf("%5d  %s", tp$n, tp$t), sep = "\n")

other <- o %>% filter(!sheet_sha256 %in% new, value_status == "published") %>% select(series_id, period, other_release = release_id, other_text = published_text)
x <- no %>% filter(value_status == "published") %>% inner_join(other, by = c("series_id", "period"), relationship = "many-to-many") %>% filter(other_release != release_id) %>%
  group_by(sheet_sha256, address) %>% summarise(equal = any(published_text == other_text), .groups = "drop") %>%
  left_join(src %>% select(sheet_sha256, publication_id), by = "sheet_sha256")
cat("\n== new values that another (already admitted) release also publishes\n")
print(x %>% group_by(publication_id) %>% summarise(cells = n(), sheets = n_distinct(sheet_sha256), equal_to_another_release = round(mean(equal), 3)))
