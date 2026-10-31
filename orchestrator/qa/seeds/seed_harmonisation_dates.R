suppressMessages({library(dplyr); library(purrr); library(stringr)})
spec <- readRDS("orchestrator/qa/cache/harmonisation_spec_phase1.rds")
p <- readRDS("orchestrator/qa/cache/harmonise_phase1.rds")$periods %>% distinct()
month_end <- function(y, m) format(seq(as.Date(sprintf("%d-%02d-01", y, m)), by = "month", length.out = 2)[2] - 1)
mon <- c(jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12)
date_of <- function(x, plain_year_end = NA) {
  x <- str_squish(x)
  last <- tail(str_split_1(x, regex(" to ", ignore_case = TRUE)), 1) %>% str_remove_all("[()]") %>% str_squish()
  if (str_detect(last, "^(19|20)\\d{2}–\\d{2}$")) {
    y <- as.integer(substr(last, 1, 4)); if (as.integer(substr(last, 6, 7)) != (y + 1) %% 100) return(NA)
    return(sprintf("%d-06-30", y + 1))
  }
  if (str_detect(last, "^(19|20)\\d{2}-(19|20)\\d{2}$") && as.integer(substr(last, 6, 9)) == as.integer(substr(last, 1, 4)) + 1) return(sprintf("%s-06-30", substr(last, 6, 9)))
  m <- str_match(last, regex("^(\\d{1,2}) ([a-z]+) ((?:19|20)\\d{2})$", ignore_case = TRUE))
  if (!is.na(m[1]) && !is.na(mon[substr(str_to_lower(m[3]), 1, 3)])) return(sprintf("%s-%02d-%02d", m[4], mon[[substr(str_to_lower(m[3]), 1, 3)]], as.integer(m[2])))
  m <- str_match(last, regex("^([a-z]+) ((?:19|20)\\d{2})$", ignore_case = TRUE))
  if (!is.na(m[1]) && !is.na(mon[substr(str_to_lower(m[2]), 1, 3)])) return(month_end(as.integer(m[3]), mon[[substr(str_to_lower(m[2]), 1, 3)]]))
  if (str_detect(last, "^(19|20)\\d{2}r?$") && !is.na(plain_year_end)) return(paste0(substr(last, 1, 4), "-", plain_year_end))
  NA
}
# Plain years are 30 June counts in these publications (prisoner census, children in care at 30 June)
plain <- c("prisoners-australia" = "06-30", "aihw-child-protection-australia" = "06-30")
all_periods <- unique(c(p$period, unlist(spec$fallback_periods))); all_periods <- all_periods[!is.na(all_periods) & nzchar(all_periods)]
default <- compact(setNames(map(all_periods, ~ { v <- date_of(.x); if (is.na(v)) NULL else v }), all_periods))
by_pub <- imap(plain, function(end, pub) { pp <- unique(p$period[which(p$publication_id == pub & str_detect(p$period, "^(19|20)\\d{2}r?$|^(19|20)\\d{2} to (19|20)\\d{2}$"))]); setNames(map(pp, ~ date_of(.x, end)), pp) })
spec$reference_dates <- c(list(default = default[order(names(default))]), by_pub)
undated <- setdiff(unique(na.omit(p$period)), c(names(default), unlist(map(by_pub, names))))
cat("reference dates:", length(default), "default +", paste(names(by_pub), lengths(by_pub), collapse = ", "), "| undated:", paste(undated, collapse = " | "), "\n")
spec <- c(list(description = paste(
  "Rules applied by harmonise() in R/harmonise.R after normalise(); see harmonisation/README.md.",
  "First version generated from the data; edit this file directly.")), spec)
dir.create("harmonisation", showWarnings = FALSE)
jsonlite::write_json(spec, "harmonisation/harmonisation_spec.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
x <- jsonlite::read_json("harmonisation/harmonisation_spec.json")
cat("written:", paste(names(x), collapse = ", "), "| split null kept:", is.null(x$split$measure$Female$measure) && "measure" %in% names(x$split$measure$Female), "\n")
print(head(unlist(spec$reference_dates$default), 8))
