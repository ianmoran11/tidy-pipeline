# Makes labels consistent across the integrated tables (ISSUES.md I35). Reruns start from
# the specs in consistency_baseline/, so the result depends only on that folder and the
# rules here. consistency_baseline/labels.csv lists every label those specs produce
# (dim, label, series), from staging every sheet.
# Usage: Rscript orchestrator/qa/seeds/seed_label_consistency.R
# Writes:
#   normalisation: control characters, autocorrected and spaced footnote markers, a trailing
#     revision r; column names; one spelling per label
#   harmonisation: period spellings from titles and the fallback; period_type; labels that
#     carry a unit or a statistic split into their parts
#   measures: unit_from_measure; family and domestic violence as scope; denominators
#   integration: column order
# unsafe lists labels left unmerged: spelling is all that separates two different
# quantities there, so merging them would make values indistinguishable.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
base <- "orchestrator/qa/seeds/consistency_baseline"
rd <- function(f) jsonlite::read_json(file.path(base, f)); wr <- function(x, p) jsonlite::write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
ns <- rd("normalisation_spec.json"); hs <- rd("harmonisation_spec.json"); ms <- rd("measure_spec.json"); is <- rd("integration_spec.json")
labels <- readr::read_csv(file.path(base, "labels.csv"), col_types = "cci", trim_ws = FALSE, na = character())
source(file.path(dirname(base), "consistency_rules.R"))  # the hand-written tables: same_as, unsafe, fixed_splits, renames, denominators

all_caps <- function(x) str_detect(x, "[A-Z]{2}") & !str_detect(x, "[a-z]")
acronyms <- c("NSW", "ACT", "NT", "SA", "WA", "FDV", "ASOC97", "ASOC08", "ASOC07", "ANZSOC", "COVID-19", "RSE", "ABS")
sentence <- function(x) {
  y <- str_to_lower(x); y <- paste0(str_to_upper(substr(y, 1, 1)), substring(y, 2))
  for (a in acronyms) y <- str_replace_all(y, regex(paste0("\\b", a, "\\b"), ignore_case = TRUE), a)
  str_replace_all(y, regex("aboriginal and torres strait islander", ignore_case = TRUE), "Aboriginal and Torres Strait Islander")
}
fold <- function(x) trimws(gsub("[^a-z0-9%$<>+]+", " ", gsub("&", " and ", tolower(x), fixed = TRUE)))
dashes <- function(x) gsub("(?<=[0-9])\\s*[-—]\\s*(?=[0-9])", "–", x, perl = TRUE)
age_label <- function(x) {
  y <- dashes(gsub("–-", "–", str_squish(sub("(?i)^aged? ", "", x, perl = TRUE)))); y <- gsub("(?<=[0-9]) to (?=[0-9])", "–", y, perl = TRUE)
  year <- function(n) if (n == "1") "1 year" else paste(n, "years")
  m <- str_match(y, "(?i)^([0-9]+)–([0-9]+)(?: years?)?$"); if (!is.na(m[1])) return(sprintf("%s–%s years", m[2], m[3]))
  m <- str_match(y, "(?i)^([0-9]+)(?: years?)?$"); if (!is.na(m[1])) return(year(m[2]))
  m <- str_match(y, "(?i)^([0-9]+)(?: years?)?(?: and| &| or)? (?:over|more)$|^([0-9]+)\\+(?: years)?$"); if (!is.na(m[1])) return(paste(year(coalesce(m[2], m[3])), "and over"))
  m <- str_match(y, "(?i)^(?:under |< ?)([0-9]+)(?: years?)?$"); if (!is.na(m[1])) return(paste("Under", year(m[2])))
  x
}

# ---- clean: what every label passes through --------------------------------------------
marker <- which(map_lgl(ns$clean, ~ str_detect(.x$pattern, "\\[a-z\\]\\{1,2\\}")))
ns$clean[[marker]]$pattern <- "(?:\\s*\\(\\s*(?:[a-z]{1,2}|[0-9]{1,2})\\s*\\))+$"  # also "INDIGENOUS( c)"
ns$clean <- c(list(list(pattern = "[\\x00-\\x1F\\x7F]", replace = " ")), ns$clean,  # "ACT\177Total"
              list(list(pattern = "\\s*[©®]$", replace = ""),     # Excel autocorrected a "(c)" or "(r)" footnote marker
                   list(pattern = "(?<=[0-9])r$", replace = ""),  # "2011r"
                   list(pattern = "^'(?=[A-Za-z])", replace = "")))  # "'Females"; "'000" keeps its apostrophe
clean <- function(x) { for (rule in ns$clean) x <- gsub(rule[["pattern"]], rule[["replace"]], x, perl = TRUE); x }
labels <- labels %>% mutate(label = clean(label)) %>% group_by(dim, label) %>% summarise(series = sum(series), .groups = "drop")

# ---- column names ----------------------------------------------------------------------
for (from in names(renames)) {
  to <- renames[[from]]
  ns$dimension_names <- map(ns$dimension_names, ~ if (identical(.x, from)) to else .x); ns$dimension_names[[from]] <- to
  if (!is.null(ns$values[[from]])) { ns$values[[to]] <- c(ns$values[[to]], ns$values[[from]]); ns$values[[from]] <- NULL }
  if (!is.null(hs$split[[from]])) { hs$split[[to]] <- c(hs$split[[to]], hs$split[[from]]); hs$split[[from]] <- NULL }
  labels$dim[labels$dim == from] <- to
}

# ---- splits ----------------------------------------------------------------------------
new_splits <- list(); put <- function(d, l, e) new_splits[[d]][[l]] <<- e
keyed <- function(d, l) !is.null(hs$split[[d]][[l]]) || !is.null(new_splits[[d]][[l]])
replaced <- function(...) list(`_replace` = list("measure", "unit"), ...)
for (d in names(fixed_splits)) for (l in names(fixed_splits[[d]])) put(d, l, fixed_splits[[d]][[l]])

# "MALES (%)", "Males %", "% 1": a label plus a unit, usually also copied into measure
unit_of <- c("%" = "%", "no." = "no.", "NO." = "no.", "no" = "no.", "NO" = "no.")
dims <- setdiff(unique(labels$dim), c("measure", "unit", "period", "population", "state", "scope", "estimate_type", "reference_date"))
for (i in which(labels$dim %in% dims)) {
  d <- labels$dim[i]; l <- labels$label[i]
  m <- str_match(l, "^(.*?)\\s*(?:\\((%|no\\.?|NO\\.?)\\)|(%))$"); p <- str_match(l, "^% ([0-9]+|Total)$")
  stem <- if (!is.na(m[1])) m[2] else if (!is.na(p[1])) p[2] else next
  mark <- if (!is.na(m[1])) coalesce(m[3], m[4]) else "%"
  if (stem == "" || keyed(d, l)) next
  u <- unname(unit_of[mark]); e <- list(); e[[d]] <- if (d == "age_group") age_label(stem) else if (all_caps(stem)) sentence(stem) else stem
  # crime_type labels ("Robbery(%)") sit beside a real measure ("Victims reporting ..."): only the unit moves
  put(d, l, c(e, if (d == "crime_type") list(unit = u, `_replace` = list("unit")) else list(measure = if (u == "%") "Proportion" else "Number", unit = u, `_replace` = list("measure", "unit"))))
}

# measure labels that hold a unit, or a dimension
measure_labels <- unique(labels$label[labels$dim == "measure"]); elsewhere <- unique(labels$label[labels$dim %in% dims])
units <- "months?|mths|years|weeks|hours|days|\\$|'000|%|no\\.?|NO\\.?"
unit_name <- function(u) { u <- tolower(u); case_when(u %in% c("month", "months", "mths") ~ "months", u %in% c("no", "no.") ~ "no.", TRUE ~ u) }
for (l in setdiff(measure_labels, c(names(same_as$measure), elsewhere))) {
  if (keyed("measure", l)) next
  m <- str_match(l, paste0("^(.*?)\\s*\\((", units, ")\\)?$"))  # "Mean (months)", "Median Months)" is below
  if (is.na(m[1])) m <- str_match(l, "(?i)^(mean|median) (months?|mths)\\)?$")
  if (is.na(m[1]) || m[2] == "") next
  put("measure", l, list(measure = if (all_caps(m[2])) sentence(gsub("EARNNGS", "EARNINGS", m[2])) else m[2], unit = unit_name(m[3])))
}

# ---- periods ---------------------------------------------------------------------------
periods <- unique(labels$label[labels$dim == "period"])
period_label <- function(p) {
  q <- dashes(sub("\\( ", "(", p))
  q <- sub("(?i)^30 june ([0-9]{4})$", "\\1", q, perl = TRUE)
  q <- sub("^December ([0-9]{4})$", "Dec \\1", q)
  q <- sub("^([0-9]{4})–[0-9]{2}([0-9]{2})$", "\\1–\\2", q)  # "2021-2022"
  q <- sub("^(200[0-9])–([0-9])$", "\\1–0\\2", q)  # "2008–9"
  if (str_detect(p, "^[0-9]{4}-06-01$")) q <- paste("June", substr(p, 1, 4))
  q
}
same_as$period <- setNames(map_chr(periods, period_label), periods); same_as$period <- same_as$period[same_as$period != names(same_as$period)]
for (p in unique(same_as$period[str_detect(same_as$period, "^June [0-9]{4}$")])) hs$reference_dates$default[[p]] <- paste0(substr(p, 6, 9), "-06-30")
for (r in unique(str_subset(names(hs$fallback_periods), ".")))  hs$fallback_periods[[r]] <- dashes(hs$fallback_periods[[r]])
for (r in fallback_releases) hs$fallback_periods[[r]] <- dashes(r)  # releases added since the first version
rule <- which(map_lgl(hs$from_title, ~ .x$dimension == "period" && str_detect(.x$pattern, "January")))
hs$from_title[[rule]]$replace <- list(list("(?i)^30 June ([0-9]{4})$", "\\1"), list("^December ([0-9]{4})$", "Dec \\1"))
# Pooled and multi-year periods share a reference_date with single years, but are different quantities
type_of <- function(p) {
  m <- str_match(p, "^([0-9]{4})–([0-9]{2})$")
  if (!is.na(m[1])) { n <- (as.integer(m[3]) - as.integer(substr(m[2], 3, 4))) %% 100; return(if (n %in% 2:3) sprintf("Pooled %d years", n) else NA_character_) }
  m <- str_match(p, "([0-9]{4})(?:–[0-9]{2})? to ([0-9]{4})(?:–([0-9]{2}))?")
  if (is.na(m[1])) return(NA_character_)
  end <- if (is.na(m[4])) as.integer(m[3]) else as.integer(m[3]) + 1L
  sprintf("Range of %d years", end - as.integer(m[2]) + (if (is.na(m[4])) 1L else 0L))
}
canonical_periods <- unique(c(periods[!periods %in% names(same_as$period)], same_as$period))
for (p in canonical_periods) { ty <- type_of(p); if (!is.na(ty) && !keyed("period", p)) put("period", p, list(period_type = ty)) }
hs$split$period <- map(hs$split$period, function(e) { ty <- type_of(e[["period"]] %||% ""); if (!is.na(ty)) e[["period_type"]] <- ty; e })

# ---- one spelling per label ------------------------------------------------------------
ages <- unique(labels$label[labels$dim == "age_group"]); ages <- setdiff(ages[!map_lgl(ages, ~ keyed("age_group", .x))], unsafe$label[unsafe$dim == "age_group"])
same_as$age_group <- c(same_as$age_group, setNames(map_chr(ages, age_label), ages))
badness <- function(x) 8 * all_caps(x) + 4 * str_detect(x, "&") + 4 * str_detect(x, " /|/ ") + 2 * str_detect(x, "[0-9]-[0-9]") +
  2 * str_detect(x, "[a-z]–[a-z]") + (str_count(x, "\\b[A-Z][a-z]") > 1)
skip_dims <- c("measure", "unit", "period", "state", "court_level", "age_group", "reference_date")
candidates <- labels %>% filter(!dim %in% skip_dims) %>% mutate(key = fold(label)) %>%
  filter(!map2_lgl(dim, label, keyed), !paste(dim, key) %in% paste(unsafe$dim, fold(unsafe$label))) %>%
  group_by(dim, key) %>% filter(n() > 1) %>% arrange(badness(label), desc(series), .by_group = TRUE) %>% mutate(to = first(label)) %>% ungroup() %>% filter(label != to)
for (d in unique(candidates$dim)) { x <- filter(candidates, dim == d); same_as[[d]] <- c(same_as[[d]], setNames(x$to, x$label)) }
for (l in setdiff(measure_labels[all_caps(measure_labels)], c(elsewhere, names(same_as$measure)))) if (!keyed("measure", l)) same_as$measure[l] <- sentence(l)

# ---- apply -----------------------------------------------------------------------------
for (d in names(same_as)) {
  if (is.null(ns$values[[d]])) ns$values[[d]] <- list()
  for (l in names(same_as[[d]])) if (same_as[[d]][[l]] != l) ns$values[[d]][[l]] <- unname(same_as[[d]][l])
}
for (d in names(ns$values)) for (l in names(ns$values[[d]])) {  # normalise() makes one pass: resolve chains
  v <- ns$values[[d]][[l]]; seen <- l
  while (!is.null(ns$values[[d]][[v]]) && !identical(ns$values[[d]][[v]], v) && !v %in% seen) { seen <- c(seen, v); v <- ns$values[[d]][[v]] }
  ns$values[[d]][[l]] <- v
}
# Only this seed's spellings, not the whole value map: some entries are for a publication's
# own table labels ("Defendants finalised" -> "Federal defendants finalised")
final <- function(d, l) { if (!is.character(l)) return(l); x <- clean(l); m <- same_as[[d]][x]; if (is.null(same_as[[d]]) || is.na(m)) x else unname(m) }
for (d in names(new_splits)) for (l in names(new_splits[[d]])) hs$split[[d]][[l]] <- new_splits[[d]][[l]]
# labels other specs write must be canonical too: split parts, title rules, subjects and flags
parts <- function(e) { for (f in setdiff(names(e), "_replace")) if (!is.null(e[[f]])) e[[f]] <- if (f == "measure" && all_caps(e[[f]])) sentence(final(f, e[[f]])) else final(f, e[[f]]); e }
hs$split <- imap(hs$split, function(d_entries, d) map(d_entries, parts))
hs$from_title <- map(hs$from_title, function(r) {  # [[ ]]: r$value would partly match "values"
  if (!is.null(r[["values"]])) r[["values"]] <- map(r[["values"]], ~ final(r[["dimension"]], .x))
  if (!is.null(r[["value"]])) r[["value"]] <- final(r[["dimension"]], r[["value"]])
  r
})
ms$subjects <- map(ms$subjects, ~ map(.x, parts)); ms$title_flags <- map(ms$title_flags, function(f) { f$set <- parts(f$set); f })
ms$subjects <- imap(ms$subjects, function(p, pub) imap(p, function(e, s) subject_rule(e, s, pub)))
ms$unit_from_measure <- unit_from_measure
ms$title_flags <- c(denominators, title_units, ms$title_flags); ms$replace_labels$measure <- list("Proportion")
ms$replace_labels$population <- c(ms$replace_labels$population, replace_population)
is$dimension_order <- c(list("period_type"), is$dimension_order)

wr(ns, "normalisation/normalisation_spec.json"); wr(hs, "harmonisation/harmonisation_spec.json"); wr(ms, "measures/measure_spec.json"); wr(is, "integration/integration_spec.json")
cat("spellings:", sum(lengths(same_as)), "| splits:", sum(lengths(new_splits)), "| renames:", length(renames), "| denominators:", length(denominators), "\n")
