# Labels that carry more than one dimension (read-only).
suppressMessages({library(dplyr); library(purrr); library(stringr)})
d <- targets::tar_read(data_normalised)
fixed <- c("row", "col", "address", ".value")
pairs <- map_dfr(d, function(s) map_dfr(s$tables, function(t) {
  recs <- t$tidy_table_list; n <- length(recs)
  dims <- setdiff(unique(unlist(map(recs, names))), fixed)
  bind_rows(
    map_dfr(dims, ~ tibble(dimension = .x, value = vapply(recs, function(r) as.character(r[[.x]] %||% NA)[1], ""))),
    map_dfr(setdiff(names(t$meta_data_list), c("table_title", "notes", "source", "table_subtitle")),
            ~ tibble(dimension = .x, value = rep(paste(unlist(t$meta_data_list[[.x]]), collapse = " "), n))))
})) %>% filter(!is.na(value)) %>% count(dimension, value, name = "records")
saveRDS(pairs, "orchestrator/qa/cache/normalised_pairs.rds")

rules <- list(
  sex = "\\b(male|males|female|females|men|women|boys|girls)\\b",
  indigenous_status = "\\b(indigenous|non-indigenous|aboriginal|torres strait|first nations)\\b",
  state = "\\b(new south wales|victoria|queensland|south australia|western australia|tasmania|northern territory|australian capital territory|nsw|vic\\.?|qld|tas\\.?)\\b",
  period = "\\b(19|20)\\d{2}(–\\d{2})?\\b",
  measure = "^(mean|median|average)\\b|\\b(rate|ratio|per cent|percentage|proportion)\\b|\\(%\\)|\\(no\\.\\)|\\(\\$\\)"
)
hits <- imap_dfr(rules, function(re, target) pairs %>% filter(dimension != target, !(target == "measure" & dimension %in% c("unit", "estimate_type")),
                                                               str_detect(str_to_lower(value), re)) %>% mutate(carries = target))
cat("distinct (dimension, label) pairs:", nrow(pairs), "\n\n")
print(hits %>% group_by(carries) %>% summarise(labels = n_distinct(paste(dimension, value)), records = sum(records), in_dimensions = paste(head(names(sort(table(dimension), decreasing = TRUE)), 6), collapse = ", ")), width = 250)
set.seed(7)
for (t in names(rules)) {
  x <- hits %>% filter(carries == t) %>% arrange(desc(records)) %>% head(40) %>% slice_sample(n = 6)
  cat("\n--", t, "inside other dimensions, e.g.\n"); for (k in seq_len(nrow(x))) cat(sprintf("   %s = \"%s\"  (%d records)\n", x$dimension[k], str_trunc(x$value[k], 90), x$records[k]))
}
both <- pairs %>% filter(str_detect(str_to_lower(value), rules$sex), str_detect(str_to_lower(value), rules$indigenous_status))
cat("\n-- labels with BOTH sex and Indigenous status:", nrow(both), "\n"); print(head(both %>% arrange(desc(records)), 8), width = 200)
