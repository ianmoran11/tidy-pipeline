# Distinct (dimension, label) pairs across every record in the data target
suppressMessages({library(dplyr); library(purrr)})
d <- targets::tar_read(data)
x <- d[[which(lengths(map(d, "tables")) > 0)[1]]]
str(x$tables[[1]]$tidy_table_list[[1]]); str(x$tables[[1]]$meta_data_list)
reserved <- c("row", "col", "address", ".value")
pairs <- map_dfr(d, function(s) map_dfr(s$tables, function(t) {
  recs <- t$tidy_table_list
  dims <- setdiff(unique(unlist(map(recs, names))), reserved)
  bind_rows(
    map_dfr(dims, function(dm) tibble(dimension = dm, value = vapply(recs, function(r) as.character(r[[dm]] %||% NA)[1], ""))),
    map_dfr(names(t$meta_data_list), function(dm) tibble(dimension = dm, value = as.character(unlist(t$meta_data_list[[dm]])), meta = TRUE)))
}))
counts <- pairs %>% count(dimension, value, name = "records")
saveRDS(counts, "orchestrator/qa/cache/raw_value_counts.rds")
cat("distinct dimension names:", n_distinct(counts$dimension), "| distinct (dimension, value):", nrow(counts), "\n")
