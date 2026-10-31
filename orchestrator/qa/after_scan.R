suppressMessages({library(dplyr); library(purrr); library(stringr)})
h <- targets::tar_read(data_harmonised)
fixed <- c("row", "col", "address", ".value", ".derived", "reference_date")
pairs <- map_dfr(h, function(s) map_dfr(s$tables, function(t) {
  dims <- setdiff(unique(unlist(map(t$tidy_table_list, names))), fixed)
  bind_rows(tibble(dimension = character(), value = character()),
            map_dfr(dims, ~ tibble(dimension = .x, value = vapply(t$tidy_table_list, function(r) as.character(r[[.x]] %||% NA)[1], ""))))
})) %>% filter(!is.na(value)) %>% count(dimension, value, name = "records")
rules <- list(sex = "\\b(male|males|female|females|men|women|boys|girls)\\b", indigenous_status = "\\b(indigenous|non-indigenous|aboriginal|torres strait|first nations)\\b",
  state = "\\b(new south wales|victoria|queensland|south australia|western australia|tasmania|northern territory|australian capital territory|nsw|vic\\.?|qld|tas\\.?)\\b",
  period = "\\b(19|20)\\d{2}(–\\d{2})?\\b", measure = "^(mean|median|average)\\b|\\b(rate|ratio|per cent|percentage|proportion)\\b|\\(%\\)|\\(no\\.\\)|\\(\\$\\)")
hits <- imap_dfr(rules, function(re, target) pairs %>% filter(dimension != target, !(target == "measure" & dimension %in% c("unit", "estimate_type", "measure_transformation")), str_detect(str_to_lower(value), re)) %>% mutate(carries = target)) %>%
  distinct(dimension, value, records)
cat("compound labels left:", nrow(hits), "(", sum(hits$records), "records ) | stacked characteristic/category records left:", sum(pairs$records[pairs$dimension == "characteristic"]), "\n")
print(hits %>% group_by(dimension) %>% summarise(labels = n(), records = sum(records), e.g. = str_trunc(first(value), 50)) %>% arrange(desc(records)), n = 25)
