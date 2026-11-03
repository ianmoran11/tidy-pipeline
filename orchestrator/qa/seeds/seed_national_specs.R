# Spec entries for the sheets admitted on 2026-11-03 ("group 2"): ABS Corrective
# Services (June quarter 2026), the Personal Safety Survey 2021-22 and its topic releases
# (partner violence, sexual violence, stalking, childhood abuse), Personal Fraud 2024-25,
# AIHW youth detention population, young people returning to supervision, youth justice
# and child protection, health of people in prisons, and RoGS 2026 child protection and
# youth justice.
# Rerunnable: it sets only its own entries, so run it after seed_label_consistency.R and
# seed_aihw_rogs_specs.R. Labels that mean something else in other publications are
# split in publication_split, which applies to these publications only.
# Usage: Rscript orchestrator/qa/seeds/seed_national_specs.R
# Writes:
#   normalisation: one name for concepts the agents named twice; quarter and month
#     spellings; "All" states; Personal Fraud RSE titles as estimate_type
#   harmonisation: Corrective Services quarters and months joined to their year headings
#     (combine); period_type for quarters; measure, unit and estimate_type splits per
#     publication; reference dates
#   measures: a subject for every title; title flags; default measures; totals that give
#     way to the title's population
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(rlang); library(unpivotr)})
rd <- function(p) jsonlite::read_json(p); wr <- function(x, p) jsonlite::write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
ns <- rd("normalisation/normalisation_spec.json"); hs <- rd("harmonisation/harmonisation_spec.json"); ms <- rd("measures/measure_spec.json")
CS <- "corrective-services-australia"; PF <- "personal-fraud"; PSS <- "personal-safety-australia"; SV <- "sexual-violence"
PV <- "partner-violence"; CA <- "childhood-abuse"; ST <- "stalking"; YD <- "aihw-youth-detention-population-australia"
YR <- "aihw-young-people-returning-youth-justice"; YC <- "aihw-youth-justice-child-protection"; PH <- "aihw-health-people-australias-prisons"
RC <- "pc-rogs-child-protection"; RY <- "pc-rogs-youth-justice"
SURVEYS <- c(PSS, SV, PV, CA, ST); PUBS <- c(CS, PF, SURVEYS, YD, YR, YC, PH, RC, RY)
psplit <- function(pub, dim, label, parts) hs$publication_split[[pub]][[dim]][[label]] <<- parts

# Normalisation: names ---------------------------------------------------------------
# One concept, two names from different agents (never in the same record)
same_name <- c(emergency_fund_capacity = "emergency_funds_capacity", emergency_funds_availability = "emergency_funds_capacity",
  emotional_abuse_anxiety_or_fear = "emotional_abuse_anxiety_fear", emotional_abuse_cohabitation_status = "emotional_abuse_cohabitation",
  first_emotional_abuse_cohabitation_status = "emotional_abuse_first_occurrence_cohabitation",
  emotionally_abusive_partner_assault_status = "emotionally_abusive_partner_assault", first_violence_cohabitation = "first_partner_violence_while_cohabiting",
  time_since_last_emotional_abuse = "time_since_emotional_abuse", main_language_at_home = "home_language",
  household_cash_flow_status = "household_cash_flow_problems", current_study_status = "study_status",
  partner_violence_work_absence = "work_absence_due_to_partner_violence", suicide_self_harm_risk = "suicide_self_harm_risk_status",
  head_injury_in_prison_status = "prison_head_injury_status", self_harm_in_prison_status = "prison_self_harm_status",
  # RoGS child protection: "Population at 30 June" vs "at 31 December" (as child protection, ISSUES I36)
  population_reference_date = "scope")
for (n in names(same_name)) ns$dimension_names[[n]] <- same_name[[n]]
ns$values$scope[["Population at 30 June"]] <- "At 30 June"; ns$values$scope[["Population at 31 December"]] <- "At 31 December"
psplit(PH, "state", "All", list(state = "Australia"))  # prison health: all jurisdictions (Youth Justice uses "All" too)
ns$values$rate_standardisation[["Age-standardised rate"]] <- "Age standardised"

# The group 2 sheets, normalised with the names above
for (f in c("R/field_sets.R", "R/published_value.R", "R/expand_excel_range.R", "R/one_enhead.R", "R/blank_value_cells.R", "R/process_recipe.R", "R/normalise.R")) source(f)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c", reference_only = "l", sheet_index = "i"), na = c("", "NA"), trim_ws = FALSE)
m <- filter(m, publication_id %in% PUBS, !reference_only, file.exists(file.path("tidy-recipes", paste0(sheet_sha256, ".json"))))
sheets <- parallel::mclapply(seq_len(nrow(m)), function(i) tryCatch(normalise(process_recipe(m[i, ], file.path("tidy-recipes", paste0(m$sheet_sha256[i], ".json"))), ns),
                                                                   error = function(e) NULL), mc.cores = 6)
labels <- function(field, pubs = PUBS) unique(unlist(map(keep(sheets, ~ !is.null(.x) && .x$source$publication_id %in% pubs),
  function(s) map(s$tables, function(t) c(t$meta_data_list[[field]], map(t$tidy_table_list, field))))))

# Normalisation: periods. Corrective Services writes "Jun Qtr 25", or "Jun Qtr" and "Apr"
# under a year heading; youth detention "Jun qtr 2021"
month <- set_names(month.name, month.abb); quarter <- c(Mar = "March", Jun = "June", Sep = "September", Dec = "December")
for (l in labels("period")) {
  to <- NULL
  if (str_detect(l, "^[A-Z][a-z]{2}$") && l %in% month.abb) to <- month[[l]]
  if (str_detect(l, "^(Mar|Jun|Sep|Dec) [Qq]tr$")) to <- paste(quarter[[substr(l, 1, 3)]], "quarter")
  if (str_detect(l, "^(Mar|Jun|Sep|Dec) [Qq]tr [0-9]{2}$")) to <- sprintf("%s quarter 20%s", quarter[[substr(l, 1, 3)]], str_sub(l, -2))
  if (str_detect(l, "^(Mar|Jun|Sep|Dec) [Qq]tr [0-9]{4}$")) to <- sprintf("%s quarter %s", quarter[[substr(l, 1, 3)]], str_sub(l, -4))
  if (!is.null(to) && is.null(ns$values$period[[l]])) ns$values$period[[l]] <- ns$values$period[[to]] %||% to
}
# Personal Fraud's RSE tables name their estimate type only in the title
for (l in grep("Relative standard error", labels("estimate_type", PF), value = TRUE)) ns$values$estimate_type[[l]] <- "Relative standard error"

# Harmonisation: periods -------------------------------------------------------------
months <- "^(January|February|March|April|May|June|July|August|September|October|November|December)$"
hs$combine$calendar_year <- list(into = "period", when = list(list(pattern = "^(March|June|September|December) quarter$", set = list(period_type = "Quarter")),
                                                              list(pattern = months, set = list(period_type = "Month"))))
# Quarters and months end on their last day; a quarter is a different quantity from the
# year or financial year that ends on the same day
for (y in 2010:2030) {
  for (i in 1:12) {
    end <- as.Date(sprintf("%d-%02d-01", y + (i == 12), i %% 12 + 1)) - 1
    hs$reference_dates$default[[paste(month.name[i], y)]] <- hs$reference_dates$default[[paste(month.name[i], y)]] %||% format(end)
    if (i %% 3 == 0) {
      q <- paste(month.name[i], "quarter", y)
      hs$reference_dates$default[[q]] <- format(end); hs$split$period[[q]] <- list(period_type = "Quarter")
    }
  }
}
# Plain years: calendar years in Corrective Services (annual averages of the months), the
# surveys (1996, 2005, 2012, 2016) and RoGS youth justice (populations at 31 December);
# 30 June in RoGS child protection ("at 30 June") and prison health (AIHW, as child protection)
for (y in 1990:2030) for (p in PUBS) {
  hs$reference_dates[[p]][[as.character(y)]] <- sprintf(if (p %in% c(RC, PH)) "%d-06-30" else "%d-12-31", y)
}

# Harmonisation: labels that carry a measure or unit ---------------------------------
# Corrective Services: "Males (Average daily number)", "Home detention (Number on first day of month)"
# Counts take their unit from unit_from_measure, so a title that names a rate wins
# (Table 3, imprisonment rates, repeats Table 2's "Males (Average daily number)")
for (dim in c("sex", "order_type", "indigenous_status", "legal_status", "prison_security", "population", "measure")) {
  for (l in labels(dim, CS)) {
    p <- str_match(l, "^(.*?)\\s*\\((Average daily number|Number on first day of month|Rate per 100,000 adult( Aboriginal and Torres Strait Islander)? population)\\)(\\s*\\([a-z]\\))*$")
    if (is.na(p[1])) next
    # A rate heading over "Crude rate" and "Age-standardised rate" rows says only the unit
    rate <- str_detect(p[3], "^Rate")
    parts <- if (rate) list(unit = "per 100,000 adult population") else list(measure = p[3])
    if (dim == "measure") parts <- c(parts, list(measure = "Rate", rate_standardisation = if (str_detect(p[2], "^Age")) "Age standardised" else "Crude"))
    else parts[[dim]] <- p[2]
    psplit(CS, dim, l, c(parts, list(`_replace` = list(if (rate) "unit" else "measure"))))
  }
}
for (m in c("Average daily number", "Number on first day of month")) ms$unit_from_measure[[m]] <- "no."  # no other publication has these
ms$replace_labels$measure <- as.list(union(unlist(ms$replace_labels$measure), "Average daily number"))
for (l in c("Crude rate", "Age-standardised rate")) psplit(CS, "measure", l, list(measure = "Rate", rate_standardisation = if (l == "Crude rate") "Crude" else "Age standardised", unit = "per 100,000 adult population"))
psplit(CS, "measure", "Ratio of age standardised rates", list(measure = "Rate ratio", rate_standardisation = "Age standardised", unit = "ratio"))
psplit(CS, "measure", "Ratio of crude rates", list(measure = "Rate ratio", rate_standardisation = "Crude", unit = "ratio"))
psplit(CS, "measure", "Ratio of Aboriginal and Torres Strait Islander to Non-Indigenous", list(measure = "Rate ratio", unit = "ratio"))
psplit(CS, "measure", "Average number on first day of month", list(measure = "Number on first day of month", unit = "no."))
psplit(CS, "measure", "Average daily number", list(measure = "Average daily number", unit = "no."))
psplit(CS, "measure", "Number", list(measure = "Number", unit = "no."))

# Surveys: an RSE's unit is its own (%); it is the RSE of a count or of a proportion
for (p in c(SURVEYS, PF)) {
  for (l in c("RSE of estimate (%)", "RSE of estimate ('000)")) psplit(p, "estimate_type", l, list(estimate_type = "Relative standard error", measure = "Number", unit = "%"))
  psplit(p, "estimate_type", "RSE of proportion (%)", list(estimate_type = "Relative standard error", measure = "Proportion", unit = "%"))
  # The topic releases put the same headings in measure (Crime Victimisation's split makes
  # them measure "Estimate")
  for (l in grep("^RSE of (estimate|proportion)", labels("measure", p), value = TRUE)) {
    psplit(p, "measure", l, list(measure = if (str_detect(l, "proportion")) "Proportion" else "Number", estimate_type = "Relative standard error", unit = "%",
                                 `_replace` = list("estimate_type", "unit")))
  }
}
# Personal Fraud headings name the offence or who is counted; the unit says count or %
# ("Experienced a scam…" is '000 in the estimate tables and the RSE of that count, in %, in
# the RSE tables; the proportion is "Victimisation rate")
for (l in grep("^(Experienced|Persons who experienced) ", labels("measure", PF), value = TRUE)) psplit(PF, "measure", l, list(measure = "Number"))
psplit(PF, "measure", "Total persons", list(measure = "Population"))
psplit(PF, "measure", "Total", list(measure = "Number"))
psplit(PF, "measure", "Reported to an authority", list(measure = "Number", authority_reporting_status = "Reported to an authority"))
psplit(PF, "measure", "Financial loss ($)", list(measure = "Financial loss", unit = "$"))

# Youth justice and child protection: column headings that name a cohort of everyone under
# supervision, detention or community-based supervision in 2022-23 ("All detention",
# "Detention only", "Supervision with child protection (%)"). The cohort is that whole
# population, split by child_protection_interaction; the table title says whether a
# count, % or rate, unless the heading says %
broad <- c(cbs = "Young people under community-based supervision during 2022–23", det = "Young people in detention during 2022–23",
           sup = "Young people under youth justice supervision during 2022–23")
cohort <- function(l) {
  base <- str_remove(l, "\\s*\\(%\\)$") |> str_remove("\\s*%$"); b <- tolower(base)
  who <- if (str_detect(b, "community-based")) broad[["cbs"]] else if (str_detect(b, "detention")) broad[["det"]] else if (str_detect(b, "supervision|youth justice clients")) broad[["sup"]]
  v <- if (str_detect(b, "^all ")) list(child_protection_interaction = NULL)
       else if (str_detect(b, "only$")) list(child_protection_interaction = "No interaction with child protection")
       else if (str_detect(b, "with child protection$")) list(child_protection_interaction = "Interaction with child protection")
  if (is.null(who) || is.null(v)) return(NULL)
  c(list(population = who), v, if (base != l) list(measure = "Proportion", unit = "%"))
}
for (l in labels("measure", YC)) {
  if (str_detect(l, "^% ")) psplit(YC, "measure", l, list(measure = paste("Proportion", str_remove(l, "^% ")), unit = "%"))
  else if (!is.null(v <- cohort(l))) psplit(YC, "measure", l, c(v, if (is.null(v$measure)) list(measure = NULL), list(`_replace` = list("population"))))
}
for (l in labels("population", YC)) {
  if (!is.null(v <- cohort(l))) psplit(YC, "population", l, c(v, list(`_replace` = list("measure", "unit"))))
  else if (str_detect(l, "^All ")) psplit(YC, "population", l, list(population = NULL))  # the title's population ("All young people with 1 or more substantiated notification")
}
sex_ind <- list("First Nations females" = list(sex = "Females", indigenous_status = "Aboriginal and Torres Strait Islander"),
                "First Nations males" = list(sex = "Males", indigenous_status = "Aboriginal and Torres Strait Islander"),
                "Non-Indigenous females" = list(sex = "Females", indigenous_status = "Non-Indigenous"),
                "Non-Indigenous males" = list(sex = "Males", indigenous_status = "Non-Indigenous"),
                "Unknown" = list(indigenous_status = "Unknown"), "All young people" = list())
for (l in names(sex_ind)) psplit(YC, "sex_and_indigenous_status", l, c(list(sex_and_indigenous_status = NULL), sex_ind[[l]]))

# Young people returning: "n" and "% who ..." columns
for (l in labels("measure", YR)) {
  if (l == "n") psplit(YR, "measure", l, list(measure = "Number", unit = "no."))
  else if (str_detect(l, "^% ")) psplit(YR, "measure", l, list(measure = paste("Proportion", str_remove(l, "^% ")), unit = "%"))
  else if (str_detect(l, "^(Number|Person-years)")) psplit(YR, "measure", l, list(measure = l, unit = "no."))
  else if (str_detect(l, "^Incidence rate")) psplit(YR, "measure", l, list(measure = "Incidence rate of return", unit = "per person-year"))
}
# Prison health: "Entrants" and "Dischargees" columns
psplit(PH, "population", "Entrants", list(population = "Prison entrants")); psplit(PH, "population", "Dischargees", list(population = "Prison dischargees"))

# RoGS: the description column reads "Number of", "Rate (per 10,000 custody nights) of"
for (p in c(RC, RY)) for (l in labels("measure", p)) {
  r <- str_match(l, "^Rate \\((per [^)]*)\\)( of)?$")
  if (!is.na(r[1])) psplit(p, "measure", l, list(measure = "Rate", unit = r[2], `_replace` = list("unit")))
  else if (str_detect(l, "^Rate per 1,000 children")) psplit(p, "measure", l, list(measure = "Rate", unit = str_remove(l, "^Rate "), `_replace` = list("unit")))
  else if (l %in% c("Number of", "Proportion of")) psplit(p, "measure", l, list(measure = str_remove(l, " of$")))
}

# Measures ---------------------------------------------------------------------------
# Survey titles name who is counted, then what they experienced: "Women aged 18 years and
# over, Experiences of violence by a male perpetrator since the age of 15, By ...". The
# subject keeps both clauses (not a "By ..." one)
for (p in c(SURVEYS, PH, YR)) ms$publication_subject_pattern[[p]] <- sub("\\(\\[\\^,\\]\\+\\)$", "([^,]+(?:,\\\\s*(?!by\\\\b)[^,]+)?)", ms$subject_pattern)
key_of <- function(cells, pub) {
  t <- str_squish(gsub(" ", " ", paste(cells, collapse = " ")))
  pattern <- ms$publication_subject_pattern[[pub]] %||% ms$subject_pattern
  str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(coalesce(str_match(t, regex(pattern, ignore_case = TRUE))[, 2], ""))))
}
titles <- bind_rows(map(sheets, function(s) {
  if (is.null(s)) return(NULL)
  own <- unlist(s$sheet_metata[["table_title"]]); pub <- s$source$publication_id
  map_dfr(s$tables, function(t) tibble(pub = pub, key = key_of(if (length(own)) own else unlist(t$meta_data_list[["table_title"]]), pub)))
})) |> distinct() |> filter(key != "")
sentence <- function(x) {
  y <- paste0(str_to_upper(substr(x, 1, 1)), substring(x, 2))
  y <- str_replace_all(y, regex("aboriginal and torres strait islander", ignore_case = TRUE), "Aboriginal and Torres Strait Islander")
  y <- str_replace_all(y, regex("\\bfirst nations\\b", ignore_case = TRUE), "First Nations")
  y <- str_replace_all(y, regex("\\bhepatitis c\\b", ignore_case = TRUE), "hepatitis C")
  y <- str_replace_all(y, "\\batc\\b", "ATC")
  y <- str_replace_all(y, "\\b(january|february|march|april|may|june|july|august|september|october|november|december)\\b", str_to_title)
  y <- str_replace_all(y, "\\s+–\\s*|\\s*–\\s+", " – ") |> str_replace_all("currenthealth", "current health")  # "2013– 30 June"; a title typo
  str_replace_all(y, "\\bindigenous\\b", "Indigenous")
}
# Who is counted: the title's subject before "by ...", without the table's own qualifiers
who <- function(key) str_remove(key, "^[a-z]: ") |> str_remove(":.*$") |> str_remove("\\s+by\\s.*$") |> str_remove("\\s+\\((number|number and per cent)\\)$") |>
  str_remove("^(number of|all) ") |> str_replace_all("(?<=[a-z])–(?=[a-z])", "-")
subject <- function(pub, key) {
  if (pub == YD) {
    s <- list(); k <- who(key)
    if (str_detect(k, "^first nations ")) s$indigenous_status <- "Aboriginal and Torres Strait Islander"
    if (str_detect(k, "^non-indigenous ")) s$indigenous_status <- "Non-Indigenous"
    k <- str_remove(k, "^(first nations|non-indigenous) ") |> str_remove(" \\(all ages\\)")
    if (str_detect(k, "^australian population")) return(c(s, list(population = sentence(k), measure = "Population")))
    return(c(s, list(population = sentence(k))))
  }
  if (pub == PF) {
    offence <- c("card fraud" = "Card fraud", "identity theft" = "Identity theft", "online impersonation" = "Online impersonation", "scams" = "Scams")
    o <- str_match(key, "^experiences of (card fraud|identity theft|online impersonation|scams) in")[, 2]
    if (!is.na(o)) return(list(population = "Persons aged 15 years and over", crime_type = offence[[o]]))
    if (str_detect(key, "^experiences( and reporting)? of")) return(list(population = "Persons aged 15 years and over"))
    return(list(population = sentence(who(key))))
  }
  if (pub %in% c(SURVEYS, PH, YR)) {  # "Female prison entrants, average number of births, by ..."; "Young people released …, who returned …"
    parts <- str_split_fixed(key, ",\\s*", 2)
    what <- str_squish(str_remove(parts[2], ":.*$"))
    # "by a previous partner" is part of who is counted here, not a breakdown
    first <- if (pub == YR) who(parts[1]) else str_squish(str_remove(parts[1], ":.*$"))  # YR: "young people by age at first supervision ..."
    return(c(list(population = sentence(first)), if (nzchar(what)) list(scope = sentence(what))))
  }
  list(population = sentence(who(key)))
}
for (i in which(titles$pub %in% c(PF, SURVEYS, YD, YR, YC, PH))) ms$subjects[[titles$pub[i]]][[titles$key[i]]] <- subject(titles$pub[i], titles$key[i])

# Corrective Services and RoGS titles name an indicator, so each gets who is counted by hand
atsi <- "Aboriginal and Torres Strait Islander"; cbc <- "Persons in community-based corrections"; ftc <- "Persons in full-time custody"; rate <- "per 100,000 adult population"
cs <- tibble::tribble(
  ~key, ~population, ~measure, ~unit, ~indigenous_status,
  "aboriginal and torres strait islander imprisonment rates", ftc, "Imprisonment rate", rate, atsi,
  "aboriginal and torres strait islander persons in community-based corrections", cbc, NA, NA, atsi,
  "aboriginal and torres strait islander persons in community-based corrections rates", cbc, "Rate", rate, atsi,
  "aboriginal and torres strait islander persons in full-time custody", ftc, NA, NA, atsi,
  "community-based corrections", cbc, NA, NA, NA,
  "community-based corrections rates", cbc, "Rate", rate, NA,
  "federal sentenced persons in full-time custody", "Federal sentenced persons in full-time custody", NA, NA, NA,
  "imprisonment rates", ftc, "Imprisonment rate", rate, NA,
  "persons in community-based corrections", cbc, NA, NA, NA,
  "persons in community-based corrections rates", cbc, "Rate", rate, NA,
  "persons in corrective services", "Persons in corrective services", NA, NA, NA,
  "persons in full-time custody", ftc, NA, NA, NA,
  "prisoner receptions into full-time custody", "Prisoner receptions into full-time custody", NA, NA, NA,
  "prisoner releases from full-time custody", "Prisoner releases from full-time custody", NA, NA, NA)
rogs <- tibble::tribble(
  ~pub, ~key, ~population, ~measure,
  RY, "absconds from unescorted leave", "Periods of unescorted leave", NA,
  RY, "assaults in custody", "Young people in custody and staff", NA,
  RY, "case plans prepared/reviewed within six weeks of commencing a sentenced order", "Young people commencing a sentenced order", NA,
  RY, "completion of community-based supervised orders", "Community-based supervised orders", NA,
  RY, "cost per group conference", "Group conferences", "Cost per group conference",
  RY, "cost per young person subject to community-based supervision", "Young people under community-based supervision", "Cost per young person",
  RY, "cost per young person subject to detention-based supervision", "Young people in detention", "Cost per young person",
  RY, "custody nights", "Young people in detention", "Custody nights",
  RY, "deaths in custody", "Young people in custody", NA,
  RY, "escapes from detention and escorted movement", "Young people in custody", NA,
  RY, "group conferences resulting in an agreement", "Group conferences", NA,
  RY, "proportion of young people in detention attending education and training", "Young people in detention of compulsory school age", NA,
  RY, "proportion of young people released from sentenced supervision", "Young people released from sentenced supervision", NA,
  RY, "self-harm and attempted suicide in custody", "Young people in custody", NA,
  RY, "serious assaults in custody", "Young people in custody and staff", NA,
  RY, "state and territory government real recurrent expenditure on youth justice services", "Youth justice services", "Real recurrent expenditure",
  RY, "state and territory government recurrent expenditure on youth justice services", "Youth justice services", "Recurrent expenditure",
  RY, "total youth population aged 10–17 years", "Young people aged 10–17 years", "Population",
  RY, "utilisation of detention centres", "Detention centres", NA,
  RY, "young people aged 10–17 years in detention", "Young people aged 10–17 years in detention", NA,
  RY, "young people aged 10–17 years in detention and under community-based supervision", "Young people aged 10–17 years under supervision", NA,
  RY, "young people aged 10–17 years under community-based supervision", "Young people aged 10–17 years under community-based supervision", NA,
  RY, "young people in detention and under community-based supervision", "Young people under supervision", NA,
  RC, "aboriginal and torres strait islander children aged 0–17 years in care by relationship with caregiver", "Aboriginal and Torres Strait Islander children aged 0–17 years in care", NA,
  RC, "activity group unit costs", "Child protection services", NA,
  RC, "child protection notifications", "Child protection notifications", NA,
  RC, "children aged 0–16 years exiting out-of-home care to a permanency arrangement", "Children aged 0–16 years exiting out-of-home care to a permanency arrangement", NA,
  RC, "children aged 0–17 years admitted to and discharged from care and protection orders", "Children aged 0–17 years admitted to or discharged from care and protection orders", NA,
  RC, "children aged 0–17 years admitted to and discharged from out-of-home-care by indigenous status", "Children aged 0–17 years admitted to or discharged from out-of-home care", NA,
  RC, "children aged 0–17 years commencing intensive family support services", "Children aged 0–17 years commencing intensive family support services", NA,
  RC, "children aged 0–17 years in care", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in care by indigenous status and length of time in continuous care", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in care by indigenous status and placement type", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in care by indigenous status and whether on a care and protection order", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in care placed with relatives/kin by indigenous status", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in care who were the subject of a substantiation of sexual abuse", "Children aged 0–17 years in care", NA,
  RC, "children aged 0–17 years in notifications", "Children aged 0–17 years in notifications", NA,
  RC, "children aged 0–17 years on a care and protection order and exiting care during the year by number of placements", "Children aged 0–17 years on a care and protection order exiting care during the year", NA,
  RC, "children aged 0–17 years who exited care during the year by indigenous status and length of time spent in care", "Children aged 0–17 years who exited care during the year", NA,
  RC, "children aged 0–17 years with documented case plans", "Children aged 0–17 years in care", NA,
  RC, "children aged 2–17 years in out-of-home care for two years or more", "Children aged 2–17 years in out-of-home care for two years or more", NA,
  RC, "children in care and in a home-based placement", "Children in care in a home-based placement", NA,
  RC, "children on guardianship/custody orders by proficiency level", "Students", NA,
  RC, "disproportionality ratios for aboriginal and torres strait islander children aged 0–17 years", "Aboriginal and Torres Strait Islander children aged 0–17 years", "Disproportionality ratio",
  RC, "expenditure on care services", "Care services", NA,
  RC, "expenditure on intensive family support services", "Intensive family support services", "Real expenditure",
  RC, "finalised investigations substantiated", "Finalised investigations", NA,
  RC, "foster carer households with children placed", "Foster carer households", NA,
  RC, "government real recurrent expenditure on all child protection services", "Child protection services", "Real recurrent expenditure",
  RC, "population aged 0–17 years", "Children aged 0–17 years", "Population",
  RC, "relative/kinship carer households with children placed", "Relative/kinship carer households", NA,
  RC, "response time to commence investigation from notification date", "Investigations", NA,
  RC, "response time to complete investigation from commencement date", "Investigations", NA,
  RC, "response time to complete investigation from notification date", "Investigations", NA,
  RC, "state and territory government real recurrent expenditure on care services", "Care services", "Real recurrent expenditure")
for (i in seq_len(nrow(cs))) { e <- as.list(cs[i, -1]); ms$subjects[[CS]][[cs$key[i]]] <- e[!is.na(unlist(e))] }
for (i in seq_len(nrow(rogs))) { e <- as.list(rogs[i, c("population", "measure")]); ms$subjects[[rogs$pub[i]]][[rogs$key[i]]] <- e[!is.na(unlist(e))] }
# RoGS keys the table didn't list: who is counted is the subject, as for AIHW
for (i in which(titles$pub %in% c(RC, RY))) if (is.null(ms$subjects[[titles$pub[i]]][[titles$key[i]]])) {
  message("RoGS title without a hand subject: ", titles$key[i]); ms$subjects[[titles$pub[i]]][[titles$key[i]]] <- list(population = sentence(who(titles$key[i])))
}
missing <- setdiff(titles$key[titles$pub == CS], names(ms$subjects[[CS]]))
if (length(missing)) message("Corrective Services titles without a subject: ", paste(missing, collapse = " | "))

# Counts unless a measure is named; the age-standardised cube is at 30 June
for (p in c(CS, YD, YC, YR, PH)) ms$default_measure[[p]] <- "Number"
ms$publication_title_flags[[CS]] <- list(
  list(pattern = "^Table [0-9]+: Persons in community-based corrections rates, .*30 June 20[0-9]{2} to 30 June", set = list(scope = "At 30 June")),
  list(pattern = "^Table [0-9]+: Community-based corrections rates, by Indigenous status and state/territory, 2017", set = list(scope = "At 30 June")),
  list(pattern = "^Table [0-9]+: Persons in community-based corrections, selected characteristics, by state/territory, 30 June", set = list(scope = "At 30 June")))
ms$publication_title_flags[[YD]] <- list(list(pattern = "on an average night", set = list(measure = "Average nightly number", unit = "no.")))
# Stacked tables that differ in the measure ("(number)", "(%)", "(rate per 10,000)") or in
# what the year counts
ms$publication_title_flags[[YC]] <- list(
  list(pattern = "\\(%\\)\\s*$", set = list(measure = "Proportion", unit = "%")),
  list(pattern = "\\(rate per 10,000\\)\\s*$", set = list(measure = "Rate", unit = "per 10,000")),
  list(pattern = "\\(number\\)\\s*$", set = list(measure = "Number", unit = "no.")),
  list(pattern = "by year of most recent contact", set = list(scope = "Year of most recent contact with a child protection service")),
  list(pattern = "by year of active child protection service", set = list(scope = "Year of active child protection service")),
  list(pattern = "^Table [A-Z]?[0-9]+[a-z]?\\.?[a-z]?: Young people aged 10–17 ", set = list(age_group = "10–17 years")))
# "(% of those with 1 or more substantiated notification)": a proportion of a subgroup
yc_titles <- unique(unlist(map(keep(sheets, ~ !is.null(.x) && .x$source$publication_id == YC), function(s) map(s$tables, ~ unlist(.x$meta_data_list[["table_title"]])))))
for (sfx in unique(na.omit(str_match(str_squish(yc_titles), "\\((% of [^)]*)\\)\\s*$")[, 2]))) {
  ms$publication_title_flags[[YC]] <- c(ms$publication_title_flags[[YC]], list(list(pattern = paste0("\\(", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", sfx), "\\)\\s*$"),
                                                                                  set = list(measure = paste("Proportion", str_remove(sfx, "^% ")), unit = "%"))))
}
# Survey totals ("Total women", "Total persons who ...") are the title's population
for (p in c(SURVEYS, PF)) for (l in grep("^(Total|TOTAL|All women aged)", labels("population", p), value = TRUE)) psplit(p, "population", l, list(population = NULL))

# One spelling per dimension label in these publications: labels that differ only in
# case, dashes or spacing ("Experienced Abuse", "Non–Indigenous") take the spelling the
# normalisation spec already gives other publications, else the most common one
not_dims <- c("row", "col", "address", ".value", "period", "period_type", "population", "scope", "measure", "unit", "estimate_type", "state",
              "table_title", "table_subtitle", "notes", "source", "stub_heading", "annotations", "errata", "sheet_description")
counts <- bind_rows(map(keep(sheets, Negate(is.null)), function(s) bind_rows(map(s$tables, function(t) {
  if (!length(t$tidy_table_list)) return(NULL)
  d <- as.data.frame(data.table::rbindlist(t$tidy_table_list, fill = TRUE))
  meta <- t$meta_data_list[setdiff(names(t$meta_data_list), not_dims)]
  for (n in names(meta)) if (!n %in% names(d)) d[[n]] <- paste(unlist(meta[[n]]), collapse = " ")
  f <- setdiff(names(d), not_dims); f <- f[vapply(f, function(n) is.character(d[[n]]), TRUE)]
  if (!length(f)) return(NULL)
  tibble(pub = s$source$publication_id, field = rep(f, each = nrow(d)), label = unlist(d[f], use.names = FALSE)) |> filter(!is.na(label))
}))))
spell_key <- function(x) str_squish(gsub("\\s*/\\s*", "/", gsub("\\s*[-–—]\\s*", "-", tolower(x))))
cnt <- counts |> count(pub, field, label, name = "N") |> mutate(k = spell_key(label))
for (g in split(cnt, list(cnt$field, cnt$k), drop = TRUE)) {
  if (n_distinct(g$label) < 2) next
  field <- g$field[1]; tot <- g |> group_by(label) |> summarise(N = sum(N)) |> arrange(-N)
  pref <- coalesce(intersect(tot$label, unlist(ns$values[[field]]))[1], tot$label[1])
  for (i in which(g$label != pref)) if (is.null(hs$publication_split[[g$pub[i]]][[field]][[g$label[i]]])) psplit(g$pub[i], field, g$label[i], set_names(list(pref), field))
}

wr(ns, "normalisation/normalisation_spec.json"); wr(hs, "harmonisation/harmonisation_spec.json"); wr(ms, "measures/measure_spec.json")
cat("subjects:", sum(lengths(ms$subjects[PUBS])), "| publication splits:", sum(unlist(map(hs$publication_split[PUBS], lengths))),
    "| periods:", sum(grepl("quarter|^[A-Z][a-z]{2}$", names(ns$values$period))), "\n")
