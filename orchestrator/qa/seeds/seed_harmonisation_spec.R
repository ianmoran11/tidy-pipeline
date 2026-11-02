# One-off: write the first version of harmonisation/harmonisation_spec.json.
# Edit the JSON directly afterwards.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
source("R/field_sets.R"); source("R/harmonise.R")
d <- targets::tar_read(data_normalised)
ATSI <- "Aboriginal and Torres Strait Islander"
cap1 <- function(s) paste0(toupper(substring(s, 1, 1)), substring(s, 2))
states <- c("new south wales" = "NSW", "victoria" = "Vic.", "queensland" = "Qld", "south australia" = "SA", "western australia" = "WA",
            "tasmania" = "Tas.", "northern territory" = "NT", "australian capital territory" = "ACT")

# ---- from_title: hand-written rules ------------------------------------------------
months <- "January|February|March|April|May|June|July|August|September|October|November|December"
from_title <- list(
  list(dimension = "state", pattern = paste0("(?<![A-Za-z])(", paste(tools::toTitleCase(names(states)), collapse = "|"), ")(?![A-Za-z])"), values = as.list(states)),
  list(dimension = "state", pattern = "–\\s*(Australia)(?![A-Za-z])", value = "Australia"),
  list(dimension = "court_level", pattern = "(?<![A-Za-z])(Higher Courts|Magistrates'? Courts|Children's Courts)(?![A-Za-z])",
       values = list("higher courts" = "Higher Courts", "magistrates' courts" = "Magistrates' Courts", "magistrates courts" = "Magistrates' Courts", "children's courts" = "Children's Courts")),
  list(dimension = "estimate_type", pattern = "(?<![A-Za-z])(Relative standard errors?|Standard errors?)(?![A-Za-z])",
       values = list("standard error" = "Standard error", "standard errors" = "Standard error", "relative standard error" = "Relative standard error", "relative standard errors" = "Relative standard error")),
  list(dimension = "indigenous_status", pattern = "^Table [A-Z]?[0-9.]+[a-z]?:? (Aboriginal and Torres Strait Islander)", value = ATSI),
  list(dimension = "period", pattern = paste0("(?<![0-9])((?:[0-9]{1,2} )?(?:", months, ") (?:19|20)[0-9]{2})(?![0-9])")),
  list(dimension = "period", pattern = "(?<!to )(?<![0-9–-])((?:19|20)[0-9]{2}[–-][0-9]{2})\\s*(?:\\([^)]*\\))?\\s*(?=/|$)", replace = list(c("^([0-9]{4})-([0-9]{2})$", "\\1–\\2"))),
  list(dimension = "period", pattern = ", ((?:19|20)[0-9]{2})\\s*(?=/|$)")
)

# ---- unstack: old recipes with characteristic + category -----------------------------
unstack <- list(characteristic = list(value_from = "category", names = list(
  "Age" = "age_group", "Age group" = "age_group", "Court level" = "court_level", "Duration from initiation to finalisation" = "case_duration",
  "Method of finalisation" = "method_of_finalisation", "Principal offence" = "principal_offence", "Sentence outcomes" = "principal_sentence", "Sex" = "sex")))

# ---- split: generated from rules, one explicit entry per label ------------------------
null <- function(...) { x <- list(...); x }   # helper so NULL entries survive: use list(name = NULL) via setNames
p <- function(...) { a <- list(...); a }
stat_dims <- c(age_group = "age", case_duration = "case duration", duration = "duration", sentence_length = "sentence length",
               parole_order_length = "parole order length", time_on_remand = "time on remand", times_proceeded_against = "times proceeded against")
ind_of <- function(x) case_when(str_detect(x, regex("^non[-–—]indigenous", TRUE)) ~ "Non-Indigenous",
                                str_detect(x, regex("^(indigenous|aboriginal)", TRUE)) ~ ATSI,
                                str_detect(x, regex("^all\\b", TRUE)) ~ "Total",
                                str_detect(x, regex("unknown", TRUE)) ~ "Unknown", TRUE ~ NA_character_)
remove <- function(dim) setNames(list(NULL), dim)

split_rule <- function(dim, v) {
  lv <- str_to_lower(v)
  # 1. statistics in a category dimension -> measure (+ unit); category becomes Total
  if (dim %in% names(stat_dims)) {
    m <- str_match(v, regex("^(Mean|Median)(?: (age|order length|aggregate sentence length|times proceeded against))?(?: \\((years|weeks|months)\\))?$", ignore_case = TRUE))
    if (!is.na(m[1])) {
      concept <- if (!is.na(m[3])) str_replace(str_to_lower(m[3]), "^order length$", "parole order length") else stat_dims[[dim]]
      out <- c(list(measure = paste(cap1(str_to_lower(m[2])), concept)), if (!is.na(m[4])) list(unit = str_to_lower(m[4])), setNames(list("Total"), dim), list(`_replace` = list("measure", "unit")))
      return(out)
    }
  }
  if (dim == "age_group" && v %in% c("Proportion of all offenders", "Rate ratio Indigenous/non-Indigenous")) return(c(list(measure = v, age_group = "Total"), list(`_replace` = list("measure"))))
  # 2. sex inside another dimension
  if (dim == "measure" && str_detect(lv, "^(males?|females?)$")) return(c(list(sex = if (str_detect(lv, "^f")) "Females" else "Males"), remove("measure")))
  m <- str_match(v, regex("^(Male|Female) (imprisonment rate|rate)$", TRUE))
  if (dim == "measure" && !is.na(m[1])) return(list(sex = paste0(cap1(str_to_lower(m[2])), "s"), measure = cap1(str_to_lower(m[3]))))
  m <- str_match(v, regex("^Total (males|females) .+$", TRUE))
  if (dim %in% c("age_group", "principal_offence") && !is.na(m[1])) return(c(list(sex = cap1(str_to_lower(m[2]))), setNames(list("Total"), dim)))
  # 3. Indigenous status inside another dimension
  m <- str_match(v, regex("^(Indigenous|Non[-–]Indigenous|All) (children.*)$", TRUE))
  if (dim == "population" && !is.na(m[1])) return(list(indigenous_status = ind_of(m[2]), population = cap1(str_to_lower(m[3]))))
  if (dim == "population" && str_detect(lv, "^unknown indigenous status$")) return(list(indigenous_status = "Unknown", population = "Children"))
  if (dim %in% c("population", "group", "subgroup") && str_detect(lv, "^(indigenous|non-indigenous|aboriginal and torres strait islander)( prisoners)?$")) return(c(list(indigenous_status = ind_of(v)), remove(dim)))
  if (dim == "measure" && str_detect(lv, "^(aboriginal and torres strait islander|indigenous|non-indigenous|indigenous status unknown)$")) return(c(list(indigenous_status = ind_of(v)), remove("measure")))
  if (dim == "measure" && str_detect(lv, "^aboriginal and torres strait islander \\(%\\)$")) return(list(indigenous_status = ATSI, measure = "Proportion", unit = "%"))
  if (dim == "indigenous_status" && lv == "non-indigenous rate") return(c(list(indigenous_status = "Non-Indigenous", measure = "Rate"), list(`_replace` = list("measure"))))
  if (dim == "indigenous_status" && str_detect(lv, "^rate ratio indigenous/non-indigenous$")) return(c(list(measure = "Rate ratio Indigenous/non-Indigenous"), remove("indigenous_status"), list(`_replace` = list("measure"))))
  # 4. state inside another dimension, and (%) / (no.) units
  m <- str_match(v, regex("^(.+?)\\s*\\((%|no\\.)\\)$", TRUE))
  if (!is.na(m[1]) && dim == "measure" && str_to_lower(m[2]) %in% names(states)) return(list(state = states[[str_to_lower(m[2])]], measure = "Proportion", unit = m[3], `_replace` = list("unit")))
  if (!is.na(m[1]) && dim == "state" && str_to_lower(m[2]) %in% names(states)) return(list(state = states[[str_to_lower(m[2])]], unit = m[3], `_replace` = list("unit")))
  if (!is.na(m[1]) && dim %in% c("principal_offence", "sentence_length")) return(c(setNames(list(m[2]), dim), list(unit = m[3], `_replace` = list("unit"))))
  # 5. period inside another dimension
  m <- str_match(v, "^(Not reunified|Reunified|Did not receive a third-party order|Received a third-party order) in ((?:19|20)[0-9]{2}–[0-9]{2})$")
  if (!is.na(m[1])) return(setNames(list(m[2], m[3]), c(dim, "period")))
  m <- str_match(v, "^Median length \\(number of days in ((?:19|20)[0-9]{2}–[0-9]{2})\\)$")
  if (dim == "measure" && !is.na(m[1])) return(list(measure = "Median length", unit = "days", period = m[2]))
  m <- str_match(v, "^(Percentage of all children substantiated) in ((?:19|20)[0-9]{2}–[0-9]{2})$")
  if (dim == "measure" && !is.na(m[1])) return(list(measure = m[2], period = m[3]))
  m <- str_match(v, "^(Change|Indicative change \\(excluding classification impacts\\))(?: from)? ((?:19|20)[0-9]{2} to (?:19|20)[0-9]{2})$")
  if (dim == "measure" && !is.na(m[1])) return(list(measure = m[2], period = m[3]))
  # 6. Report on Government Services rates held in generic dimensions
  if (dim %in% c("section", "group", "subgroup") && str_detect(lv, "rate per 100")) return(c(list(measure = v), remove(dim), list(`_replace` = list("measure"))))
  NULL
}

fixed <- c("row", "col", "address", ".value")
pairs <- map_dfr(d, function(s) map_dfr(s$tables, function(t) {
  dims <- setdiff(unique(unlist(map(t$tidy_table_list, names))), fixed)
  bind_rows(tibble(dimension = character(), value = character()),
            map_dfr(dims, ~ tibble(dimension = .x, value = vapply(t$tidy_table_list, function(r) as.character(r[[.x]] %||% NA)[1], ""))),
            map_dfr(setdiff(names(t$meta_data_list), c("table_title", "table_subtitle", "notes", "source")),
                    ~ tibble(dimension = .x, value = paste(unlist(t$meta_data_list[[.x]]), collapse = " "))))
})) %>% filter(!is.na(value)) %>% distinct()
# category values become their characteristic's dimension after unstacking
pairs <- bind_rows(pairs, pairs %>% filter(dimension == "category") %>% mutate(dimension = "age_group"))

split <- list()
for (k in seq_len(nrow(pairs))) {
  rule <- split_rule(pairs$dimension[k], pairs$value[k])
  if (!is.null(rule)) split[[pairs$dimension[k]]][[pairs$value[k]]] <- rule
}
# split dimensions whose labels other splits also set come first (state before measure)
split <- split[c(intersect(c("state", "indigenous_status", "sex"), names(split)), setdiff(names(split), c("state", "indigenous_status", "sex")))]
cat("split entries:", sum(lengths(split)), "across", length(split), "dimensions:", paste(names(split), lengths(split), collapse = ", "), "\n")

# ---- fallback periods ----------------------------------------------------------------
m <- readr::read_csv("source_metadata.csv", show_col_types = FALSE, col_types = readr::cols(.default = "c"), trim_ws = FALSE)
rp <- unique(na.omit(m$reference_period))
fallback <- setNames(map(rp, function(x) {
  if (str_detect(x, "^[0-9]{4}-[0-9]{2}$") && as.integer(substr(x, 6, 7)) == (as.integer(substr(x, 3, 4)) + 1) %% 100) return(sub("-", "–", x))
  if (str_detect(x, "^[0-9]{4}-[0-9]{2}$")) return(paste(month.name[as.integer(substr(x, 6, 7))], substr(x, 1, 4)))
  x
}), rp)
fallback <- fallback[map_lgl(names(fallback), ~ fallback[[.x]] != .x)]

spec <- list(from_title = from_title, split = split, unstack = unstack, fallback_periods = fallback, reference_dates = list(default = list()))
saveRDS(spec, "orchestrator/qa/cache/harmonisation_spec_phase1.rds")

# ---- phase 1 dry run: contradictions and the period labels that need dates ----------
errors <- character(); periods <- list()
for (i in seq_along(d)) {
  h <- tryCatch(harmonise(d[[i]], jsonlite::fromJSON(jsonlite::toJSON(spec, auto_unbox = TRUE, null = "null"), simplifyVector = FALSE)), error = function(e) e)
  if (inherits(h, "error")) { errors <- c(errors, conditionMessage(h)); next }
  pp <- unique(unlist(map(h$tables, ~ map_chr(.x$tidy_table_list, ~ .x$period %||% NA_character_))))
  periods[[length(periods) + 1]] <- tibble(publication_id = h$source$publication_id, period = pp[!is.na(pp)])
}
cat("contradictions:", length(errors), "\n"); cat(head(errors, 8), sep = "\n")
saveRDS(list(errors = errors, periods = bind_rows(periods)), "orchestrator/qa/cache/harmonise_phase1.rds")
