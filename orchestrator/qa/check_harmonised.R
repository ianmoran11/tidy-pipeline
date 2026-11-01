suppressMessages({library(dplyr); library(purrr); library(stringr)})
n <- targets::tar_read(data_normalised); h <- targets::tar_read(data_harmonised)
fixed <- function(x) unlist(map(x$tables, ~ map(.x$tidy_table_list, ~ unlist(.x[c("row", "col", "address", ".value")]))))
same <- sum(map2_lgl(n, h, ~ identical(fixed(.x), fixed(.y))))
recs <- sum(map_int(h, ~ sum(map_int(.x$tables, ~ length(.x$tidy_table_list)))))
cat("sheets:", length(h), "| sheets with identical row/col/address/.value:", same, "| records:", recs, "\n\n")
g <- targets::tar_read(harmonisation_gaps)
cat("== gaps by publication\n"); print(as.data.frame(g$by_publication), row.names = FALSE)
cat("\n== periods without a reference date\n"); print(as.data.frame(g$undated_periods), row.names = FALSE)
cat("\n== derived dimensions (records)\n"); print(as.data.frame(g$derived %>% group_by(dimension) %>% summarise(records = sum(n), publications = n_distinct(publication_id)) %>% arrange(desc(records))), row.names = FALSE)

# before/after examples
files <- targets::tar_read(recipe_sheets)$recipe_path; sha <- sub("\\.json$", "", basename(files))
show <- function(pred, label) {
  for (i in seq_along(h)) for (k in seq_along(h[[i]]$tables)) {
    recs_h <- h[[i]]$tables[[k]]$tidy_table_list
    j <- which(map_lgl(recs_h, pred))[1]
    if (!is.na(j)) {
      before <- n[[i]]$tables[[k]]$tidy_table_list[[j]]; after <- recs_h[[j]]
      title <- str_trunc(paste(unlist(h[[i]]$sheet_metata$table_title), collapse = " "), 110)
      fmt <- function(r) { r <- r[!names(r) %in% c("row", "col")]; paste(names(r), map_chr(r, ~ paste(.x, collapse = "//")), sep = "=", collapse = " | ") }
      cat(sprintf("\n-- %s\n   title:  %s\n   before: %s\n   after:  %s\n", label, title, str_trunc(fmt(before), 260), str_trunc(fmt(after), 300)))
      return(invisible())
    }
  }
}
show(~ grepl("(^|,)state(,|$)", .x$.derived) && identical(.x$state, "ACT"), "state from the title")
show(~ grepl("court_level", .x$.derived), "court level from the title")
show(~ grepl("estimate_type", .x$.derived), "estimate type from the title")
show(~ identical(.x$indigenous_status, "Non-Indigenous") && identical(.x$population, "Children in out-of-home care"), "split: population")
show(~ identical(.x$measure, "Imprisonment rate") && !is.null(.x$sex), "split: sex in measure")
show(~ identical(.x$measure, "Median age") && identical(.x$age_group, "Total"), "split: statistic row")
show(~ identical(.x$period, "May 2021") && grepl("period", .x$.derived), "period fallback")
show(~ identical(.x$period, "Reunified") || (identical(.x$reunification_status, "Reunified")), "split: period in label")
multi <- sum(map_int(h, ~ sum(map_int(.x$tables, ~ sum(map_int(.x$tidy_table_list, function(r) sum(lengths(r) != 1)))))))
cat("\nrecords fields holding more than one value:", multi, "\n")
