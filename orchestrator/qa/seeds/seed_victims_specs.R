# Adds spec entries for the two ABS victims publications (Crime Victimisation, Australia
# and Recorded Crime – Victims) from their staged per-sheet output. Rerunnable: it
# replaces the entries it wrote before. Input: an RDS of rows (one per record, with pub,
# subject and title) made by running extraction, normalise, harmonise and identify on
# the victims sheets (see orchestrator/qa/stage_sheets.R).
# Usage: Rscript orchestrator/qa/seeds/seed_victims_specs.R <rows.rds>
# Writes:
#   normalisation: upper-case labels -> sentence case (acronyms kept); RSE spellings;
#     measure spellings
#   harmonisation: "RSE of X" labels -> X + estimate_type, so an RSE carries the same
#     labels as its estimate; calendar-year reference dates for Recorded Crime – Victims
#     (31 December). Survey column headings such as "PERSONS" stay in `measure`: the
#     tables have their own population labels, so they can't become a population
#   measures: title subjects -> population (+ crime_type / victim_offence /
#     indigenous_status / sex); '000 -> Number
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr)})
rows <- readRDS(commandArgs(TRUE)[1])
pubs <- c("crime-victimisation-australia", "recorded-crime-victims")
rd <- function(p) jsonlite::read_json(p); wr <- function(x, p) jsonlite::write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
acronyms <- c("NSW", "ACT", "NT", "SA", "WA", "RSE", "MOE", "ABS", "ANZSOC", "LGA", "SA4", "SEIFA", "IRSD", "CBD", "MV", "GCCSA")
sentence <- function(x) {
  y <- str_to_lower(x); y <- paste0(str_to_upper(substr(y, 1, 1)), substring(y, 2))
  for (a in acronyms) y <- str_replace_all(y, regex(paste0("\\b", a, "\\b"), ignore_case = TRUE), if (a == "MOE") "MoE" else a)
  y
}
all_caps <- function(x) str_detect(x, "[A-Z]{2}") & !str_detect(x, "[a-z]") & nchar(x) > 3

# ---- normalisation -----------------------------------------------------------------
ns <- rd("normalisation/normalisation_spec.json")
skip_dims <- c("row", "col", "address", ".value", ".derived", "sheet", "pub", "subject", "title", "period", "reference_date", "state", "unit")
long <- rows %>% select(-any_of(skip_dims)) %>% mutate(across(everything(), as.character)) %>%
  pivot_longer(everything(), names_to = "dim", values_to = "label", values_drop_na = TRUE) %>% distinct()
hs0 <- rd("harmonisation/harmonisation_spec.json")  # labels other specs are keyed on must keep their spelling
keyed <- c(unlist(lapply(hs0$split, names)), unlist(lapply(rd("measures/measure_spec.json")$replace_labels, unlist)))
caps <- long %>% filter(all_caps(label), !label %in% keyed) %>% mutate(to = sentence(label))
added_norm <- 0
for (i in seq_len(nrow(caps))) {
  d <- caps$dim[i]; l <- caps$label[i]
  if (is.null(ns$values[[d]])) ns$values[[d]] <- list()
  if (is.null(ns$values[[d]][[l]])) { ns$values[[d]][[l]] <- caps$to[i]; added_norm <- added_norm + 1 }
}
fixed_values <- list(
  estimate_type = c("RSE" = "Relative standard error", "RSE (%)" = "Relative standard error", "Relative standard error (%)" = "Relative standard error",
                    "RELATIVE STANDARD ERROR" = "Relative standard error", "MoE" = "Margin of error", "Margin of error (%)" = "Margin of error",
                    "Estimate" = "Estimate", "ESTIMATE" = "Estimate"),
  measure = c("PROPORTION" = "Proportion", "PROPORTIONS" = "Proportion", "Proportions" = "Proportion", "Reporting Rate" = "Reporting rate",
              "REPORTING RATE" = "Reporting rate", "VICTIMISATION RATE" = "Victimisation rate", "Victimisation Rate" = "Victimisation rate"))
# Agents sometimes gave a column heading or the whole title a second name, estimate_type
# ("RSE of persons", "Percents", "Table 4a ...: Relative standard error"). The heading is also
# in `measure`, so estimate_type keeps only what kind of estimate it is
et <- setdiff(unique(long$label[long$dim == "estimate_type"]), c("Relative standard error", "Margin of error", "Estimate", "Standard error"))
fixed_values$estimate_type[et] <- ifelse(str_detect(et, regex("relative standard error|\\bRSE\\b", ignore_case = TRUE)), "Relative standard error",
                                  ifelse(str_detect(et, regex("margin of error|\\bMoE\\b", ignore_case = TRUE)), "Margin of error", "Estimate"))
for (d in names(fixed_values)) for (l in names(fixed_values[[d]])) { if (is.null(ns$values[[d]])) ns$values[[d]] <- list(); ns$values[[d]][[l]] <- unname(fixed_values[[d]][l]) }
for (d in names(ns$values)) for (l in names(ns$values[[d]])) {  # normalise() makes one pass: resolve chains
  v <- ns$values[[d]][[l]]; seen <- l
  while (!is.null(ns$values[[d]][[v]]) && !identical(ns$values[[d]][[v]], v) && !v %in% seen) { seen <- c(seen, v); v <- ns$values[[d]][[v]] }
  ns$values[[d]][[l]] <- v
}
wr(ns, "normalisation/normalisation_spec.json")
norm <- function(d, l) { m <- ns$values[[d]][[l]]; if (is.null(m)) l else m }  # labels as normalise() now leaves them

# ---- harmonisation -----------------------------------------------------------------
hs <- rd("harmonisation/harmonisation_spec.json")
# The split entries this script writes are listed under _victims_seed (dimension -> labels),
# so reruns replace them; harmonise() reads only the documented sections
for (d in names(hs[["_victims_seed"]])) hs$split[[d]][unlist(hs[["_victims_seed"]][[d]])] <- NULL
seeded <- list(); put <- function(d, l, e) { if (is.null(hs$split[[d]])) hs$split[[d]] <<- list(); hs$split[[d]][[l]] <<- e; seeded[[d]] <<- c(seeded[[d]], l) }
rse <- "^(?:RSE|Relative standard error)(?: of)?[ ]+(.+)$"
labels <- long %>% mutate(n = map2_chr(dim, label, norm)) %>% distinct(dim, n) %>%
  bind_rows(tibble(dim = "period", n = unique(na.omit(rows$period))))  # "RSE OF 2019–21"
r <- labels %>% filter(str_detect(n, regex(rse, ignore_case = TRUE)), dim != "estimate_type")
split_add <- 0
for (i in seq_len(nrow(r))) {
  rest <- str_match(r$n[i], regex(rse, ignore_case = TRUE))[, 2]
  rest <- sub("^estimates?( \\(%\\))?$", "estimate", rest)
  e <- list(); e[[r$dim[i]]] <- paste0(str_to_upper(substr(rest, 1, 1)), substring(rest, 2)); e$estimate_type <- "Relative standard error"
  e[["_replace"]] <- list("estimate_type")  # a specific RSE heading wins over a coarser estimate_type label
  if (is.null(hs$split[[r$dim[i]]][[r$n[i]]])) { put(r$dim[i], r$n[i], e); split_add <- split_add + 1 }
}
# titles that agents gave as `measure` ("Table 5b ...: Relative standard error"): drop them, so
# measure comes from the unit, and keep only the kind of estimate
for (l in labels$n[labels$dim == "measure" & str_detect(labels$n, "^Table ?[0-9]") & nchar(labels$n) > 40]) {
  e <- list(measure = NULL)
  if (str_detect(l, regex("relative standard error|\\bRSE\\b", ignore_case = TRUE))) e$estimate_type <- "Relative standard error"
  if (str_detect(l, regex("margin of error", ignore_case = TRUE))) e$estimate_type <- "Margin of error"
  if (!is.null(e$estimate_type)) e[["_replace"]] <- list("estimate_type")
  put("measure", l, e); split_add <- split_add + 1
}
iso <- unique(rows$period[str_detect(coalesce(rows$period, ""), "^(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}$")])
for (p in iso) hs$reference_dates$default[[p]] <- p  # periods given as dates
# Recorded Crime – Victims counts calendar years
years <- unique(rows$period[rows$pub == "recorded-crime-victims" & str_detect(rows$period, "^(19|20)[0-9]{2}$")])
rcv <- hs$reference_dates[["recorded-crime-victims"]] %||% list()
for (y in years) rcv[[y]] <- paste0(y, "-12-31")
hs$reference_dates[["recorded-crime-victims"]] <- rcv
fy <- unique(rows$period[rows$pub == "crime-victimisation-australia" & is.na(rows$reference_date)])
for (p in fy[str_detect(fy, "^(19|20)[0-9]{2}[–-][0-9]{1,2}$")]) {
  # financial years written oddly ("2008–9") and pooled survey years ("2008–10" = 2008–09 and 2009–10): end 30 June
  start <- as.integer(substr(p, 1, 4)); e <- sub("^.*[–-]", "", p); end <- start - start %% 10^nchar(e) + as.integer(e)
  if (end <= start) end <- end + 10^nchar(e)
  if ((end - start) %in% 1:3) hs$reference_dates$default[[p]] <- sprintf("%d-06-30", end)
}
# Crime Victimisation titles that name the crime after the subject ("PERSONS AGED 15 YEARS AND
# OVER, Victims of physical assault, by ..."); the seed owns the crime_type title rule
crime_known <- long %>% filter(dim == "crime_type") %>% mutate(n = map2_chr(dim, label, norm)) %>% distinct(n) %>% pull(n)
hs$from_title <- keep(hs$from_title, ~ .x$dimension != "crime_type")
hs$from_title[[length(hs$from_title) + 1]] <- list(dimension = "crime_type", pattern = "(?<=, )Victims of ([^,]+?)(?= by |,|$)",
  values = setNames(as.list(crime_known), str_to_lower(crime_known)))
hs[["_victims_seed"]] <- lapply(seeded, unique)
wr(hs, "harmonisation/harmonisation_spec.json")

# ---- measures ----------------------------------------------------------------------
ms <- rd("measures/measure_spec.json")
ms$measure_from_unit[["'000"]] <- "Number"
age_flags <- list(list(pattern = "age at incident(?! and report)", set = list(age_basis = "Age at incident")),
                  list(pattern = "(?<!incident and )age at report", set = list(age_basis = "Age at report")))
ms$title_flags <- c(keep(ms$title_flags, ~ is.null(.x$set$age_basis)), age_flags)
ms$default_measure[["recorded-crime-victims"]] <- "Number"
existing <- function(dim) {  # most common spelling of each label, to match titles to table labels
  x <- long %>% filter(dim == !!dim) %>% mutate(n = map2_chr(dim, label, norm)) %>% count(key = str_to_lower(n), n, sort = TRUE)
  setNames(x$n[!duplicated(x$key)], x$key[!duplicated(x$key)])
}
crime_label <- existing("crime_type"); offence_label <- existing("victim_offence")
as_label <- function(x, known) { k <- str_to_lower(str_squish(x)); if (!is.na(known[k])) unname(known[k]) else paste0(str_to_upper(substr(k, 1, 1)), substring(k, 2)) }
household <- c("break-in", "attempted break-in", "motor vehicle theft", "theft from a motor vehicle", "malicious property damage", "other theft", "selected household crimes", "household crime")
ATSI <- "Aboriginal and Torres Strait Islander"
cv_rule <- function(s) {
  s <- sub("^ersons ", "persons ", s)  # a title typo
  s <- sub("^[0-9]+[a-z]?\\. ", "", s); s <- sub("^all ", "", s)  # "15. all persons"
  sentence1 <- function(x) paste0(str_to_upper(substr(x, 1, 1)), substring(x, 2))
  if (s == "persons and households") return(list(population = "Persons and households"))
  if (str_detect(s, "^experience of selected household crimes")) return(list(population = "Households"))
  if (str_detect(s, "^experience of selected personal crimes")) return(list(population = "Persons aged 15 years and over"))
  hw <- str_match(s, "^households? (?:which|that|who) experienced (.+?)(?: in the last 12 months)?$")
  if (!is.na(hw[1])) return(c(list(population = "Households"), if (!str_detect(hw[2], "^selected")) list(crime_type = as_label(hw[2], crime_label))))
  aged <- str_match(s, "^(?:persons|people)(?: aged ([0-9]+) years and over)?(?: (.+?))?(?: in the last 12 months)?$")
  if (!is.na(aged[1])) { age <- if (!is.na(aged[2])) aged[2] else if (str_detect(s, "sexual")) "18" else "15"  # sexual assault is asked of 18+
    out <- list(population = sprintf("Persons aged %s years and over", age)); rest <- aged[3]
    if (!is.na(rest)) { x <- str_match(rest, "^who experienced (.+)$")[, 2]
      if (!is.na(x)) { if (!str_detect(x, "^selected")) out$crime_type <- as_label(x, crime_label) } else out$scope <- sentence1(rest) }
    return(out) }
  if (str_detect(s, "^females aged 18 years and over")) return(list(population = "Persons aged 18 years and over", sex = "Females"))
  hh <- str_match(s, "^household experience of (.+?)(?: in the last 12 months)?$")
  if (!is.na(hh[1])) return(list(population = "Households", crime_type = as_label(hh[2], crime_label)))
  if (s == "households") return(list(population = "Households"))
  if (str_detect(s, "^incidents( of)?")) return(list(population = "Incidents"))
  if (s == "populations") return(list(population = "Persons and households", measure = "Population estimate"))
  ex <- str_match(s, "^experience of (.+?) in the last 12 months")
  if (!is.na(ex[1])) { x <- ex[2]; one <- !str_detect(x, " and |^selected")
    return(c(list(population = if (str_detect(x, "sexual") && one) "Persons aged 18 years and over" else "Persons aged 15 years and over"), if (one) list(crime_type = as_label(x, crime_label)))) }
  v <- str_match(s, "^victims (?:of )?(.+)$")
  if (!is.na(v[1])) { x <- v[2]
    if (x %in% household) return(c(list(population = "Households"), if (!str_detect(x, "^selected|^household")) list(crime_type = as_label(x, crime_label))))
    if (str_detect(x, "^selected")) return(list(population = "Persons aged 15 years and over"))
    return(list(population = if (str_detect(x, "sexual")) "Persons aged 18 years and over" else "Persons aged 15 years and over", crime_type = as_label(x, crime_label))) }
  list(population = sentence1(s))
}
rcv_rule <- function(s) {
  out <- list(); if (str_detect(s, "^aboriginal and torres strait islander ")) { out$indigenous_status <- ATSI; s <- str_remove(s, "^aboriginal and torres strait islander ") }
  if (str_detect(s, "^estimated resident population")) return(list(population = "Persons", measure = "Estimated resident population"))
  if (str_detect(s, "^motor vehicles on register")) return(list(population = "Motor vehicles", measure = "Number on register"))
  if (str_detect(s, "^anzsoc ?(20)?23 table [0-9]+ ")) { out$offence_classification <- "ANZSOC 2023"; s <- sub("^anzsoc ?(20)?23 table [0-9]+ ", "", s) }
  if (str_detect(s, "^(person )?victimisation rates?$")) return(c(out, list(population = "Victims", measure = "Victimisation rate")))
  if (s == "proportion of victims") return(c(out, list(population = "Victims", measure = "Proportion")))
  if (str_detect(s, "^(person|all|total|number of) victims$")) return(c(out, list(population = "Victims")))
  if (str_detect(s, "^proportion \\(%\\) victims")) return(c(out, list(population = "Victims", measure = "Proportion", unit = "%")))
  v <- str_match(s, "^victims(?: (?:of )?(.+))?$")
  if (!is.na(v[1])) { out$population <- "Victims"; x <- v[2]
    fdv <- "^family and domestic violence(?:[- –]related)?(?: offences)?\\s*"
    if (!is.na(x) && str_detect(x, fdv)) { out$scope <- "Family and domestic violence-related"; x <- str_squish(str_remove(x, fdv)); if (x == "") x <- NA }
    if (!is.na(x) && !str_detect(x, "^(selected|all) ")) out$victim_offence <- as_label(x, offence_label); return(out) }
  c(out, list(population = "Victims"))  # every Recorded Crime – Victims table counts victims ("Relationship of offender to victim")
}
subjects <- rows %>% filter(pub %in% pubs, subject != "") %>% distinct(pub, subject)
added_sub <- 0
for (i in seq_len(nrow(subjects))) {
  p <- subjects$pub[i]; s <- subjects$subject[i]
  if (is.null(ms$subjects[[p]])) ms$subjects[[p]] <- list()
  if (!is.null(ms$subjects[[p]][[s]])) next
  ms$subjects[[p]][[s]] <- if (p == "recorded-crime-victims") rcv_rule(s) else cv_rule(s); added_sub <- added_sub + 1
}
wr(ms, "measures/measure_spec.json")
cat("normalisation labels added:", added_norm, "| harmonisation splits:", split_add, "| RCV reference dates:", length(years), "| subjects added:", added_sub, "\n")
