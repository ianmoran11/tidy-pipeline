suppressMessages({library(dplyr); library(purrr)})
source("R/normalise.R")
# 1. hand-made example
spec <- list(dimension_names = list(Year = "period", "State/territory" = "state"),
             values = list(state = list("NSW(a)" = "NSW", "New South Wales" = "NSW"), period = list("2019-20" = "2019–20")))
x <- list(sheet_metata = list(table_title = "Table 1"),
          tables = list(list(tidy_table_list = list(list(row = 5L, col = 2L, address = "B5", .value = "12.5", Year = "2019-20", `State/territory` = "NSW(a)"),
                                                    list(row = 5L, col = 3L, address = "C5", .value = "NSW(a)", Year = "2020-21", `State/territory` = "Vic.")),
                             meta_data_list = list(state = c("New South Wales", "Qld")))))
y <- normalise(x, spec)
str(y$tables[[1]]$tidy_table_list[[1]]); str(y$tables[[1]]$tidy_table_list[[2]][c(".value", "period", "state")]); str(y$tables[[1]]$meta_data_list)
dup <- tryCatch(normalise(list(tables = list(list(tidy_table_list = list(list(Year = "a", period = "b")), meta_data_list = list()))), spec), error = conditionMessage)
cat("duplicate check:", dup, "\n\n")

# 2. the real pipeline output
d <- targets::tar_read(data); n <- targets::tar_read(data_normalised)
stopifnot(identical(names(d), sub("^data_normalised_", "data_", names(n))) || length(d) == length(n))
flat <- function(s) map_dfr(s$tables, function(t) map_dfr(t$tidy_table_list, ~ tibble(address = .x$address, value = .x$.value, labels = list(.x[setdiff(names(.x), c("row","col","address",".value"))]))))
same_fixed <- 0; recs <- 0; changed <- 0
for (i in seq_along(d)) {
  a <- unlist(map(d[[i]]$tables, ~ map(.x$tidy_table_list, ~ unlist(.x[c("row","col","address",".value")]))))
  b <- unlist(map(n[[i]]$tables, ~ map(.x$tidy_table_list, ~ unlist(.x[c("row","col","address",".value")]))))
  same_fixed <- same_fixed + identical(a, b)
  ra <- unlist(map(d[[i]]$tables, ~ map(.x$tidy_table_list, ~ paste(names(.x), unlist(.x), collapse = "|"))))
  rb <- unlist(map(n[[i]]$tables, ~ map(.x$tidy_table_list, ~ paste(names(.x), unlist(.x), collapse = "|"))))
  recs <- recs + length(rb); changed <- changed + sum(ra != rb)
}
cat("branches:", length(n), "| branches with identical row/col/address/.value:", same_fixed, "| records:", recs, "| records with a changed name or label:", changed, "\n")
dims <- function(x) unique(unlist(map(x, ~ map(.x$tables, ~ c(unlist(map(.x$tidy_table_list, names)), names(.x$meta_data_list))))))
spec <- targets::tar_read(normalisation_spec)
cat("raw dimension names still present after normalising:", length(intersect(dims(n), names(spec$dimension_names))), "\n")
labels <- function(x, dim) unique(unlist(map(x, ~ map(.x$tables, ~ c(unlist(map(.x$tidy_table_list, ~ .x[[dim]])), unlist(.x$meta_data_list[[dim]]))))))
for (dm in c("state", "sex", "indigenous_status", "period")) {
  before <- unique(c(labels(d, dm), unlist(map(names(spec$dimension_names)[unlist(spec$dimension_names) == dm], ~ labels(d, .x)))))
  cat(sprintf("%-18s distinct labels: %d -> %d\n", dm, length(before), length(labels(n, dm))))
}
cat("state labels now:", paste(sort(labels(n, "state")), collapse = " | "), "\n")
