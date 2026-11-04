# Spec entries for the state and territory crime statistics admitted on 2026-11-04: the
# latest release of each police and crime statistics agency series (NSW BOCSAR, Victoria's
# Crime Statistics Agency, Queensland, WA, NT and ACT police), most recent year only.
# Rerunnable: it sets only its own entries, so run it after seed_national_specs.R. Almost
# everything is per publication (publication_split, publication_title_flags), so labels
# that mean something else elsewhere are untouched.
# Usage: Rscript orchestrator/qa/seeds/seed_state_specs.R
# Writes:
#   normalisation: one name for concepts the agents named twice, and one spelling per label
#     (reads the earlier publications' labels from integrated/series/, so run it after a build)
#   harmonisation: every period spelling as a financial year, calendar year, year ending a
#     month, month, quarter, day or range of years, with period_type and reference dates;
#     Victoria's Year and Year ending joined (combine), NSW months joined to their
#     reporting year; measure and unit headings split into measure, unit and population;
#     labels that name who is counted; Aboriginal status spellings
#   measures: the full title as the subject key, a population for every title, and the
#     state and a default population for every record
#   values (integration/value_spec.json): BOCSAR's symbols, and rewrites that read the
#     number in "Up 4.2%", "1.9 p.p" and "11.1x"
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(rlang); library(unpivotr)})
rd <- function(p) jsonlite::read_json(p); wr <- function(x, p) jsonlite::write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
ns <- rd("normalisation/normalisation_spec.json"); hs <- rd("harmonisation/harmonisation_spec.json"); ms <- rd("measures/measure_spec.json")
for (f in c("R/field_sets.R", "R/published_value.R", "R/expand_excel_range.R", "R/one_enhead.R", "R/blank_value_cells.R", "R/process_recipe.R",
            "R/normalise.R", "R/select_sheets.R")) source(f)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c", reference_only = "l", sheet_index = "i"), na = c("", "NA"), trim_ws = FALSE)
m <- select_sheets(m, rd("sources/dataset_selection.json")) |> filter(has_recipe, str_detect(publication_id, "^(act|nsw|nt|qld|sa|tas|vic|wa)-"))
PUBS <- unique(m$publication_id)
STATE <- c(act = "ACT", nsw = "NSW", nt = "NT", qld = "Qld", sa = "SA", tas = "Tas.", vic = "Vic.", wa = "WA")
state_of <- function(p) STATE[[sub("-.*", "", p)]]
VIC_TABLES <- grep("^vic-crime-statistics-agency-data-tables-(?!supplementary)", PUBS, value = TRUE, perl = TRUE)
AJI <- "vic-crime-statistics-agency-aboriginal-justice-indicators-dashboard"
psplit <- function(pub, dim, label, parts) hs$publication_split[[pub]][[dim]][[label]] <<- parts
ATSI <- "Aboriginal and Torres Strait Islander"

# Normalisation: names ---------------------------------------------------------------
# One concept, two names from different agents (never in the same record)
same_name <- c(incident_day_of_week = "day_of_week", incident_time_band = "time_of_day", incident_time_of_day = "time_of_day",
  incident_start_time = "time_of_day", family_incident_flag = "family_incident_status", ivo_application_status = "intervention_order_application_status",
  unsentenced_movement = "unsentenced_movement_type", bail_breach_offence_status = "breach_bail_offence_status",
  justice_data_source = "reporting_agency", bail_decision_agency = "reporting_agency", domestic_violence_related_status = "domestic_violence_status",
  alcohol_related_status = "substance_contribution", recorded_offence_category = "incident_offence_category",
  recorded_offence_subcategory = "incident_offence_subcategory", criminal_incident_offence = "recorded_incident_offence",
  incident_offence = "recorded_incident_offence", criminal_incident_charge_status = "incident_charge_status")
for (n in names(same_name)) ns$dimension_names[[n]] <- same_name[[n]]

# Measures: Victoria's tables are titled only on the workbook's Contents sheet ("Table 08"
# beside "Unique youth alleged offenders and rate per 100,000 population by sex and age -
# July 2016 to June 2026"); identify() reads those titles from sheet_titles
for (f in unique(m$xlsx_file[str_detect(m$publication_id, "^vic-")])) {
  path <- file.path("source-spreadsheets-xlsx", f)
  if (!"Contents" %in% tidyxl::xlsx_sheet_names(path)) next
  cells <- tidyxl::xlsx_cells(path, sheets = "Contents") |> filter(!is.na(character))
  for (i in which(str_detect(cells$character, "^Table [0-9]+$"))) {
    title <- cells$character[cells$row == cells$row[i] & cells$col > cells$col[i]][1]
    sha <- m$sheet_sha256[m$xlsx_file == f & m$sheets == cells$character[i]]
    if (length(sha) == 1 && !is.na(title)) ms$sheet_titles[[sha]] <- str_squish(title)
  }
}

# The state sheets, normalised with the names above; only the labels this seed reads
FIELDS <- c("period", "measure", "unit", "state", "year_ending_month", "reporting_period", "charge_counting_unit", "recorded_population_breakdown", "indigenous_status")
read_sheet <- function(i) tryCatch({
  s <- normalise(process_recipe(m[i, ], m$recipe_path[i]), ns)
  own <- unlist(s$sheet_metata[["table_title"]]) %||% unlist(ms$sheet_titles[[m$sheet_sha256[i]]])
  titles <- if (length(own)) list(own) else map(s$tables, ~ unlist(.x$meta_data_list[["table_title"]]))
  labs <- list()
  recs <- bind_rows(map(s$tables, function(t) {
    if (!length(t$tidy_table_list)) return(NULL)
    d <- as.data.frame(data.table::rbindlist(t$tidy_table_list, fill = TRUE))
    meta <- t$meta_data_list[setdiff(names(t$meta_data_list), c("table_title", "table_subtitle", "notes", "source"))]  # as harmonise() copies them
    for (n in names(meta)) if (!n %in% names(d)) d[[n]] <- paste(unlist(meta[[n]]), collapse = " ")
    # every dimension's labels, for one spelling per label (below)
    labs[[length(labs) + 1]] <<- bind_rows(lapply(setdiff(names(d), c("row", "col", "address", ".value")), function(n) {
      x <- table(as.character(d[[n]])); if (length(x)) tibble(dim = n, label = names(x), n = as.integer(x)) }))
    d <- d[, intersect(FIELDS, names(d)), drop = FALSE]; d[] <- lapply(d, as.character); distinct(d)
  }))
  list(pub = m$publication_id[i], titles = titles, recs = recs, labs = bind_rows(labs))
}, error = function(e) { message("Skipped ", m$sheet_sha256[i], ": ", conditionMessage(e)); NULL })
sheets <- compact(parallel::mclapply(seq_len(nrow(m)), read_sheet, mc.cores = 5))
rows <- bind_rows(map(sheets, ~ if (nrow(.x$recs %||% tibble())) mutate(.x$recs, pub = .x$pub)))
labels <- function(field, pubs = PUBS) if (field %in% names(rows)) unique(na.omit(rows[[field]][rows$pub %in% pubs])) else character()

# Harmonisation: periods -------------------------------------------------------------
# A 12-month span is a financial year (to June), a calendar year (to December) or "Year
# ending <month>"; longer spans are ranges of years; months, quarters and days end on their
# last day. Labels as published: "Jul 2025 - Jun 2026", "Jul-2025 to Jun-2026",
# "NSW Recorded Crime Statistics July 2025 - June 2026", "Apr-26*", "2026/Apr", "2025-07-01"
# (Queensland and WA months), "2025-07-31" (NSW custody months, shown as "Jul-25"),
# "2024 Q3 Jul-Sep", "3 months ending 2025Q3", "01APR2026"
end_of <- function(y, mo) format(as.Date(sprintf("%d-%02d-01", y + (mo == 12), mo %% 12 + 1)) - 1)
month_num <- function(x) match(tolower(substr(x, 1, 3)), tolower(month.abb))
year_of <- function(x) { x <- as.integer(x); if (x < 100) 2000L + x else x }
fy <- function(y) sprintf("%d–%02d", y - 1L, y %% 100L)
MON <- "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\.?"
span_of <- function(x) {
  r <- str_match(x, sprintf("^%s[ -]?([0-9]{2,4})\\s*(?:-|–|to)\\s*%s[ -]?([0-9]{2,4})$", MON, MON))
  if (is.na(r[1])) NULL else list(m1 = month_num(r[2]), y1 = year_of(r[3]), m2 = month_num(r[4]), y2 = year_of(r[5]))
}
month_period <- function(mo, y) list(period = paste(month.name[mo], y), period_type = "Month", date = end_of(y, mo))
period_of <- function(l) {
  x <- str_squish(str_remove(str_remove(l, "^(NSW Recorded Crime Statistics|Most recent 12-month period)\\s*"), "[*^~]+$"))
  s <- span_of(x)
  if (!is.null(s)) {
    n <- (s$y2 - s$y1) * 12 + s$m2 - s$m1 + 1; date <- end_of(s$y2, s$m2)
    if (n == 12) return(list(period = if (s$m2 == 6) fy(s$y2) else if (s$m2 == 12) as.character(s$y2) else paste("Year ending", month.name[s$m2], s$y2), date = date))
    p <- if (s$m2 == 6 && s$m1 == 7) paste(fy(s$y1 + 1L), "to", fy(s$y2)) else if (s$m2 == 12 && s$m1 == 1) paste(s$y1, "to", s$y2) else paste(month.name[s$m1], s$y1, "to", month.name[s$m2], s$y2)
    return(c(list(period = p, date = date), if (n %% 12 == 0) list(period_type = sprintf("Range of %d years", n / 12))))
  }
  r <- str_match(x, sprintf("^%s[ -]([0-9]{2,4})$", MON)); if (!is.na(r[1])) return(month_period(month_num(r[2]), year_of(r[3])))
  r <- str_match(x, sprintf("^([0-9]{4})/%s$", MON)); if (!is.na(r[1])) return(month_period(month_num(r[3]), year_of(r[2])))
  r <- str_match(x, "^([0-9]{4})-([0-9]{2})-[0-9]{2}$"); if (!is.na(r[1])) return(month_period(as.integer(r[3]), as.integer(r[2])))
  r <- str_match(x, "^([0-9]{4}) Q([1-4])\\b"); if (is.na(r[1])) r <- str_match(x, "^3 months ending ([0-9]{4})Q([1-4])$")
  if (!is.na(r[1])) { q <- 3L * as.integer(r[3]); y <- as.integer(r[2]); return(list(period = paste(month.name[q], "quarter", y), period_type = "Quarter", date = end_of(y, q))) }
  r <- str_match(x, "^([0-9]{2})([A-Z]{3})([0-9]{4})$")
  if (!is.na(r[1])) return(list(period = sprintf("%d %s %s", as.integer(r[2]), month.name[month_num(r[3])], r[4]), period_type = "Day",
                                date = sprintf("%s-%02d-%s", r[4], month_num(r[3]), r[2])))
  NULL
}
set_period <- function(pub, label, p) {
  psplit(pub, "period", label, c(list(period = p$period), if (!is.null(p$period_type)) list(period_type = p$period_type)))
  hs$reference_dates[[pub]][[p$period]] <<- p$date
}
for (pub in PUBS) for (l in labels("period", pub)) if (!is.null(p <- period_of(l)) && p$period != l) set_period(pub, l, p) else if (!is.null(p)) hs$reference_dates[[pub]][[p$period]] <- p$date
# Plain years are calendar years (court finalisations, re-offending cohorts, the AJI
# dashboard's years ending December), except: Victoria's data tables count years ending
# June (Year 2026 with Year ending June, joined by combine below); NT's "2026" is the 12
# months ending August 2026
for (pub in PUBS) for (y in 2010:2026) hs$reference_dates[[pub]][[as.character(y)]] <- sprintf("%d-12-31", y)
hs$combine$year_ending_month <- list(into = "period", when = list(list(pattern = "^[0-9]{4}$", set = setNames(list(), character()))))
for (pub in VIC_TABLES) for (y in 2010:2026) {
  for (mo in month.name) { p <- if (mo == "June") fy(y) else if (mo == "December") as.character(y) else paste("Year ending", mo, y)
    psplit(pub, "period", paste(y, mo), list(period = p)); hs$reference_dates[[pub]][[p]] <- end_of(y, match(mo, month.name)) }
  psplit(pub, "period", as.character(y), list(period = fy(y))); hs$reference_dates[[pub]][[fy(y)]] <- sprintf("%d-06-30", y)
}
NT <- "nt-northern-territory-crime-statistics"
psplit(NT, "period", "2026", list(period = "Year ending August 2026")); hs$reference_dates[[NT]][["Year ending August 2026"]] <- "2026-08-31"
psplit(NT, "state", "Northern Territory1", list(state = "NT"))
# The releases dated "2025-12" (AJI dashboard, NSW Closing the Gap targets) cover the year
# to December 2025; records without a period of their own fall back to it
hs$fallback_periods[["2025-12"]] <- "2025"
# NSW trend tables give only their span in the subtitle ("NSW Recorded Crime Statistics
# July 2016 to June 2026"); their counts, rates and ranks are for the span's last 12
# months, and their trends run to it
year_to <- function(mo, y) if (mo == 6) fy(y) else if (mo == 12) as.character(y) else paste("Year ending", month.name[mo], y)
MON_ <- str_replace(MON, "^\\(", "(?:")
nsw_span <- list(dimension = "period",
  pattern = sprintf("NSW Recorded Crime Statistics,?\\s+%s ?[0-9]{4}\\s*(?:-|–|to)\\s*(%s ?[0-9]{4})", MON_, MON_),
  replace = map(1:12, ~ list(sprintf("(?i)^%s[a-z]*\\.? ?", month.abb[.x]), paste0(month.name[.x], " "))),
  values = unlist(map(2010:2026, function(y) setNames(map(1:12, ~ year_to(.x, y)), tolower(paste(month.name, y)))), recursive = FALSE))
hs$from_title <- c(list(nsw_span), keep(hs$from_title, ~ !str_detect(.x$pattern, "NSW Recorded Crime Statistics")))
for (pub in PUBS) for (y in 2010:2026) for (mo in 1:12) hs$reference_dates[[pub]][[year_to(mo, y)]] <- end_of(y, mo)
# COVID breaches: "Total" is the 12 months shown, February 2022 to January 2023
COVID <- "nsw-bocsar-covid"
psplit(COVID, "period", "Total", list(period = "Year ending January 2023")); hs$reference_dates[[COVID]][["Year ending January 2023"]] <- "2023-01-31"
# NSW LGA workbooks put the months of their reporting year ("April") under a heading for
# the year ("NSW Recorded Crime Statistics July 2025 - June 2026")
hs$combine$reporting_period <- list(into = "period", when = list(list(pattern = "^(January|February|March|April|May|June|July|August|September|October|November|December)$", set = setNames(list(), character()))))
for (pub in PUBS) for (rp in labels("reporting_period", pub)) {
  s <- span_of(str_squish(str_remove(rp, "^NSW Recorded Crime Statistics\\s*"))); if (is.null(s)) next
  for (k in 0:((s$y2 - s$y1) * 12 + s$m2 - s$m1)) {
    mo <- (s$m1 + k - 1) %% 12 + 1; y <- s$y1 + (s$m1 + k - 1) %/% 12
    if (k >= ((s$y2 - s$y1) * 12 + s$m2 - s$m1) - 11) set_period(pub, paste(month.name[mo], rp), month_period(mo, y))
  }
}
# Trends and changes printed where a period would be: the change to the latest year. A trend
# is a significance test: "Up 4.2%" or "Down 4.2%" where significant, the average annual
# percentage change (BOCSAR's notes), else "Stable" (value spec below). Trends get no unit
# of their own (see measure_parts)
trend_of <- function(l) {
  n <- str_match(tolower(l), "^([0-9]+|two|five|ten|twenty)[ -]?(?:year|yr)")[, 2]
  if (!is.na(n) && n %in% c("two", "five", "ten", "twenty")) n <- c(two = "2", five = "5", ten = "10", twenty = "20")[[n]]
  if (is.na(n)) NULL else paste0(n, "-year trend")
}
na_null <- function(x) if (!length(x) || is.na(x)) NULL else unname(x)
for (pub in PUBS) for (l in labels("period", pub)) {
  if (str_detect(l, "^[0-9]+-year change$")) psplit(pub, "period", l, list(period = "2025", change_measure = paste("Change last", str_extract(l, "^[0-9]+"), "years"), unit = "percentage points", `_replace` = list("unit")))
  else if (str_detect(l, "trend") && !is.null(t <- trend_of(l))) psplit(pub, "period", l, list(period = "2025–26", measure = t, unit = NULL, `_replace` = list("measure", "unit")))
}
# The reporting year left on records whose period is not a month repeats their period
for (pub in PUBS) for (rp in labels("reporting_period", pub)) psplit(pub, "reporting_period", rp, list(reporting_period = NULL))

# Harmonisation: measure and unit headings --------------------------------------------
# A heading names what is shown (count, rate, rank, ratio, proportion, trend) and often
# who is counted ("Victim Reports", "Unique Alleged Offenders"), which becomes population
clean_heading <- function(l) {
  x <- str_remove_all(l, "[*^~]+|(?<=[a-z)])[0-9]$")
  x <- str_remove(x, "^(?:Jul|July|Apr|April) 20[0-9]{2} - (?:Jun|June|Mar|March) 20[0-9]{2} ")
  x <- str_remove(x, "\\s*\\((?:Jul|July)[^)]*20[0-9]{2}\\)$|\\s*\\((?:Dec-)?20[0-9]{2}\\)$|\\s*-\\s*Current Year$|\\s+(?:Jul|July) 2025 - (?:Jun|June) 2026$")
  str_squish(x)
}
who_counted <- c("victim reports" = "Victim reports", "report count" = "Victim reports", "unique victims" = "Unique victims",
  "alleged offender incidents" = "Alleged offender incidents", "alleged offender incident count" = "Alleged offender incidents",
  "unique alleged offenders" = "Unique alleged offenders", "family incident count" = "Family incidents", "family incidents" = "Family incidents",
  "unique person count" = "Unique persons", "afm counter" = "Affected family members", "oth counter" = "Other parties",
  "unique afm" = "Unique affected family members", "unique oth" = "Unique other parties", "incident count" = "Criminal incidents",
  "total incidents recorded" = "Criminal incidents", "total assaults" = "Assaults",
  "charges finalised" = NA, "total defendants with a finalised court appearance" = "Defendants with a finalised court appearance",
  "total aboriginal defendants with a finalised court appearance" = "Defendants with a finalised court appearance",
  "avos in force" = "Apprehended Violence Orders in force", "avos in force and breached ever" = "Apprehended Violence Orders in force and breached at any time",
  "avos in force and breached in qtr" = "Apprehended Violence Orders in force and breached in the quarter",
  "aboriginal adult custody population" = "Aboriginal adults in custody", "total nsw adult custody population" = "Adults in custody",
  "number of total adults in custody" = "Adults in custody", "number of total adults appearing in court" = "Adults appearing in court",
  "number of total young people in custody" = "Young people in custody", "number of total young people appearing in court" = "Young people appearing in court",
  "number of vehicles stolen" = "Stolen motor vehicles", "vehicles recovered" = "Recovered motor vehicles", "total murder victims" = "Murder victims")
denominator <- function(x) {
  r <- str_match(x, regex("per ([0-9,]+)\\s*(.*)$", ignore_case = TRUE)); if (is.na(r[1])) return(NULL)
  d <- str_squish(str_remove(str_remove(r[3], "\\)$"), "\\s*\\(.*$")) |> str_replace("\\bolder$", "over") |> str_remove("^of .*| of .*$| by .*$")
  d <- if (d %in% c("", "pop", "pop.", "population")) "population" else if (str_detect(d, "^population [0-9]+ years")) paste("population aged", str_remove(d, "^population ")) else str_remove(d, "^total ")
  if (str_detect(d, "^youth legal actions$")) d <- "young people"
  paste("per", r[2], d)
}
AVO <- "nsw-bocsar-apprehended-violence-orders"
avo_population <- function(b) if (str_detect(b, "breach")) "Breaches of Apprehended Violence Orders proceeded against" else if (str_detect(b, "persons protected")) "Persons protected by an Apprehended Violence Order" else if (str_detect(b, "commenced")) "Apprehended Violence Orders commenced" else "Apprehended Violence Orders in force"
measure_parts <- function(pub, l) {
  x <- clean_heading(l); b <- tolower(x); who <- na_null(who_counted[b])
  role <- if (str_detect(b, "^afm\\b")) "Affected family member" else if (str_detect(b, "^oth\\b")) "Other party"
  if (!is.null(role)) who <- if (str_detect(b, "unique|person")) "Unique persons" else "Family incidents"
  if (pub == AVO && str_detect(b, "^(number|rate per 100,000 population) of ")) {
    return(c(if (str_detect(b, "^rate")) list(measure = "Rate", unit = "per 100,000 population") else list(measure = "Number"), list(population = avo_population(b))))
  }
  if (str_detect(b, "fv flagged count")) return(list(measure = "Number", population = "Alleged offender incidents", family_incident_status = "Family violence flagged"))
  # AJI pathways: "Charged Count" and "Charged %" are a count and a proportion of an outcome
  outcome <- str_match(x, "^(Caution/Warning|Charge Not Proven|Charge Proven|Charged|Community Supervision|Court Finalised|Custodial Sentence|Not Charged|Not Court Finalised|Other Outcome|Other Proven Outcome|Penalty Notice|Summons Not Authorised)(?: Alleged Offender Incident)? (Count|%)$")
  if (!is.na(outcome[1])) return(list(measure = if (outcome[3] == "%") "Proportion" else "Number", unit = if (outcome[3] == "%") "%" else "no.", justice_pathway_outcome = outcome[2]))
  if (b == "percentage charged") return(list(measure = "Proportion", unit = "%", justice_pathway_outcome = "Charged"))
  base <- function(parts) c(parts, if (!is.null(role)) list(family_violence_role = role, `_replace` = list("family_violence_role")))
  # Counts that the heading says are something else first
  if (str_detect(b, "^number of incidents recorded by the nsw police force as occurring at public transport")) return(list(measure = "Number", population = "Criminal incidents at public transport premises"))
  # No unit: a trend of rates is told from a trend of counts only by the rate's unit, which
  # identify() takes from the table title ("% per year" here made the two the same)
  if (str_detect(b, "trend")) return(list(measure = trend_of(b) %||% "Trend"))
  if (str_detect(b, "percentage change|% change")) return(base(list(measure = "Percentage change", unit = "%", population = who %||% na_null(who_counted[paste(str_squish(str_remove(b, "^(afm|oth) |percentage change")), "count")]))))
  if (str_detect(b, "over.representation")) return(list(measure = "Rate ratio", unit = "ratio"))
  if (str_detect(b, "aboriginal (average|rate)")) return(list(measure = "Ratio to NSW Aboriginal rate", unit = "ratio"))
  if (str_detect(b, "ratio to nsw")) return(list(measure = "Ratio to NSW rate", unit = "ratio"))
  if (str_detect(b, "national offence index") && !str_detect(b, "rank")) return(list(measure = "National Offence Index", unit = "index"))
  if (str_detect(b, "rank")) {
    if (pub == "nsw-bocsar-info-file-offence-seriousness-ranking") return(list(measure = if (str_detect(b, "^median sentence")) "Median sentence ranking" else if (str_detect(b, "statutory")) "Median statutory maximum ranking" else "National Offence Index ranking", unit = "rank"))
    # AJI's Value Unit column says what is ranked ("Count"); the rank's own unit replaces it
    return(list(measure = if (b == "relationship rank") "Relationship rank" else "Rank", unit = "rank", `_replace` = list("unit")))
  }
  if (str_detect(b, "rate") && !str_detect(b, "^%|%$")) {
    of <- str_match(x, regex("rate per [0-9,]+ population of (.*)$", ignore_case = TRUE))[, 2]
    if (str_detect(b, "^table [0-9]+\\. annual rate")) of <- "Driving offences with a person proceeded against"
    unit <- if (str_detect(b, "^lga rate")) "per 100,000 LGA population" else if (str_detect(b, "^psa rate")) "per 100,000 PSA population" else denominator(x)
    if (is.null(unit) && pub != AJI) unit <- "per 100,000 population"
    pop <- if (!is.na(of)) str_squish(str_remove(of, "\\s*\\^$")) else who %||% na_null(who_counted[paste(str_squish(str_remove(b, "\\s*rate$")), "count")])
    # "Rate per 100,000 total adults (Dec-2025)" is of adults in custody, "(2025)" of adults appearing in court
    if (str_detect(b, "total (adults|young people)")) pop <- paste(if (str_detect(b, "adults")) "Adults" else "Young people", if (str_detect(l, "Dec-")) "in custody" else "appearing in court")
    return(c(list(measure = "Rate"), if (!is.null(unit)) list(unit = unit), if (!is.null(pop)) list(population = pop)))
  }
  if (str_detect(b, "^%|%$| % |proportion|percentage")) {
    what <- c("% breach ever" = "Proportion breached at any time", "% breach in qtr" = "Proportion breached in the quarter", "% proven" = "Proportion proven",
              "% reoffending" = "Proportion reoffending", "yr % fv of total" = "Proportion family violence related",
              "proportion of vehicles recovered" = "Proportion recovered", "alleged offender incident %" = "Proportion")[b]
    if (is.na(what)) what <- if (str_detect(b, "proceedings commenced within")) paste("Proportion with proceedings commenced within", str_extract(b, "[0-9]+ days"))
                             else if (str_detect(b, "associated with alcohol")) "Proportion associated with alcohol"
                             else if (str_detect(b, "associated with domestic")) "Proportion associated with domestic violence" else "Proportion"
    pop <- if (str_detect(b, "of assaults")) "Assaults" else if (b == "proportion of vehicles recovered") "Stolen motor vehicles" else if (b == "alleged offender incident %") "Alleged offender incidents"
    return(c(list(measure = unname(what), unit = "%"), if (!is.null(pop)) list(population = pop)))
  }
  if (str_detect(b, "population|estimated resident|pop by year")) {
    if (!is.null(who)) return(list(measure = "Number", population = who))
    if (pub == "nsw-bocsar-custody") return(list(measure = "Number"))
    pop <- if (str_detect(b, "10 to 17")) "Persons aged 10 to 17 years" else if (str_detect(b, "^aboriginal under 18")) "Aboriginal girls and women" else "Persons"
    # "2026 population" columns beside monthly counts have no period heading of their own
    return(c(list(measure = "Population", unit = "no.", population = pop), if (str_detect(b, "^20[0-9]{2} population$")) list(period = str_sub(b, 1, 4))))
  }
  if (str_detect(b, "number of days")) return(list(measure = x, unit = "days"))
  if (str_detect(b, "average number of incidents")) return(list(measure = "Average number of incidents", unit = "no."))
  if (b == "number reoffending") return(list(measure = "Number reoffending", unit = "no."))
  if (str_detect(b, "^proceedings commenced within")) return(list(measure = paste("Number with proceedings commenced within", str_extract(b, "[0-9]+ days")), unit = "no."))
  court <- c("charges finalised" = "Number finalised", "charges proven" = "Number proven", "defendants with a finalised charge" = "Number with a finalised charge",
             "defendants with a proven charge" = "Number with a proven charge")[b]
  if (!is.na(court)) return(list(measure = unname(court), unit = "no."))
  nt <- list("assaults with alcohol involved" = list(substance_contribution = "Alcohol involved"), "assaults with no alcohol involved" = list(substance_contribution = "No alcohol involved"),
             "dv involved total" = list(domestic_violence_status = "DV involved"), "dv not involved total" = list(domestic_violence_status = "DV not involved"))[[b]]
  if (!is.null(nt)) return(c(list(measure = "Number", population = "Assaults"), nt))
  if (!is.null(who)) return(base(list(measure = "Number", population = who)))
  if (str_detect(b, "^(number|count|total|record count|sum of record count|offence count|incidents recorded|offences recorded|number of .*|.* offences|.* counter|unique .*|victim reports|report count|alleged offender incident.*|family incident.*|incident count|.*unique person count|.*incident count|avos in force.*|table [0-9]+\\. (annual|monthly) number.*)$")) {
    return(base(list(measure = "Number")))
  }
  NULL
}
unmapped <- character()
for (pub in PUBS) for (l in labels("measure", pub)) {
  parts <- measure_parts(pub, l)
  if (is.null(parts)) { unmapped <- c(unmapped, paste(pub, l, sep = " | ")); next }
  parts <- parts[!map_lgl(parts, is.null)]
  # AJI titles say whose records a table counts (children, women and girls, family
  # violence); the heading's "Alleged offender incidents" is which count it is
  if (pub == AJI && !is.null(parts$population)) { parts$counted_entity <- parts$population; parts$population <- NULL }
  if (identical(parts[["measure"]], l) && length(parts) == 1) next
  psplit(pub, "measure", l, parts)
}
# Unit headings
for (pub in PUBS) for (l in labels("unit", pub)) {
  if (str_detect(l, "^Offence Rates")) psplit(pub, "unit", l, list(unit = "per 100,000 population", measure = "Rate", `_replace` = list("measure")))
  else if (str_detect(l, "^Rate \\(per")) psplit(pub, "unit", l, list(unit = denominator(l)))
  else if (l == "Count") psplit(pub, "unit", l, list(unit = "no."))
}
# The offence seriousness ranking has no period of its own; its notes date each ranking. The
# median sentence ranking was revised in 2018 from court data for 2013 to 2017, and the median
# statutory maximum ranking comes from the same cases (footnote b: a group "with no cases" has
# both calculated at the subdivision level). The National Offence Index is ABS's 2009 edition
RANK <- "nsw-bocsar-info-file-offence-seriousness-ranking"
for (l in names(hs$publication_split[[RANK]]$measure)) hs$publication_split[[RANK]]$measure[[l]] <- c(hs$publication_split[[RANK]]$measure[[l]],
  if (str_detect(l, "^Median")) list(period = "2013 to 2017", period_type = "Range of 5 years") else list(period = "2009"))
hs$reference_dates[[RANK]][["2013 to 2017"]] <- "2017-12-31"; hs$reference_dates[[RANK]][["2009"]] <- "2009-12-31"

# AJI dashboard: a "Value" column is a count or a rate, as the Value Unit column beside it
# says ("Incident count", "Incident rate"); a "Value Rank" keeps it, to say what is ranked
hs$combine$incident_value_basis <- list(into = "measure", when = list(list(pattern = "^Value( - Current Year)?$", set = setNames(list(), character()))))
for (v in c("Value", "Value - Current Year")) {
  psplit(AJI, "measure", paste(v, "Incident count"), list(measure = "Number", unit = "no."))
  psplit(AJI, "measure", paste(v, "Incident rate"), list(measure = "Rate", unit = "per 1,000 population"))
}
# AJI victims (Table 10) name the Value Unit column `unit`, so its Value Rank ranks the count or
# the rate by unit alone; the rank's own unit would replace it, so the unit is joined to the rank
hs$combine$unit <- list(into = "measure", when = list(list(pattern = "^Value Rank$", set = setNames(list(), character()))))
psplit(AJI, "measure", "Value Rank Count", list(measure = "Rank by count", unit = "rank"))
psplit(AJI, "measure", "Value Rank Rate (per 1,000 pop)", list(measure = "Rank by rate", unit = "rank"))

# Harmonisation: labels that say who is counted --------------------------------------
CS <- "nsw-bocsar-court-and-sentencing"
psplit(CS, "charge_counting_unit", "Charges", list(charge_counting_unit = NULL, population = "Charges in finalised court appearances", `_replace` = list("population")))
psplit(CS, "charge_counting_unit", "Defendants charged", list(charge_counting_unit = NULL, population = "Defendants charged in finalised court appearances", `_replace` = list("population")))
WP <- "nsw-bocsar-weapons"
psplit(WP, "recorded_population_breakdown", "POI age", list(population = "Persons of interest"))
psplit(WP, "recorded_population_breakdown", "Victim age", list(population = "Victims"))
psplit(WP, "recorded_population_breakdown", "Region", list(population = "Criminal incidents"))
# NSW and Victoria write "Aboriginal" for Aboriginal and/or Torres Strait Islander people
for (pub in PUBS) for (l in labels("indigenous_status", pub)) {
  to <- if (str_detect(l, "^(Aboriginal|Aboriginal and/or Torres Strait Islander)$")) ATSI else if (str_detect(l, "^(?i)non-aboriginal$")) "Non-Indigenous"
  if (!is.null(to)) psplit(pub, "indigenous_status", l, list(indigenous_status = to))
}

# Measures ---------------------------------------------------------------------------
# The whole title (after "Table N.") is the subject: state titles put the distinguishing
# words after a comma ("Number of non-domestic assault, domestic assault and robbery
# incidents where a firearm was recorded"; "Rate per 100,000 population of ...")
full <- sub("\\(\\[\\^,\\]\\+\\)$", "(.+)", ms$subject_pattern)
for (p in PUBS) ms$publication_subject_pattern[[p]] <- full
key_of <- function(cells) {
  t <- str_squish(gsub(" ", " ", paste(cells, collapse = " ")))
  str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(coalesce(str_match(t, regex(full, ignore_case = TRUE))[, 2], ""))))
}
titles <- bind_rows(map(sheets, function(s) tibble(pub = s$pub, key = map_chr(s$titles, key_of)))) |> distinct() |> filter(key != "")
sentence <- function(x) str_replace(x, "^(.)", toupper)
who_rules <- tibble::tribble(
  ~pub, ~key, ~population,
  "^act-", ".", "Offences and other activities",
  "alleged-offender-dataset", ".", "Persons of interest proceeded against",
  "apprehended-violence", "breach", "Breaches of Apprehended Violence Orders proceeded against",
  "apprehended-violence", "persons protected", "Persons protected by an Apprehended Violence Order",
  "apprehended-violence", "commenced", "Apprehended Violence Orders commenced",
  "apprehended-violence", "in force", "Apprehended Violence Orders in force",
  "court-and-sentencing", "mean custodial sentence", "Defendants given a custodial sentence in finalised court appearances",
  "court-and-sentencing", "convicted defendants|defendants convicted", "Defendants convicted in finalised court appearances",
  "court-and-sentencing", "proven domestic violence", "Defendants with proven domestic violence offences in finalised court appearances",
  "court-and-sentencing", "charges and defendants charged", "Charges and defendants charged in finalised court appearances",
  "court-and-sentencing", "court delay", "Finalised court appearances",
  "court-and-sentencing", "summary characteristics", "Defendants with a finalised court appearance",
  "court-and-sentencing", "appeal cases", "Appeal cases finalised in the District Court",
  "court-and-sentencing", "finalised by trial", "Defendants charged in court appearances finalised by trial",
  "court-and-sentencing", ".", "Defendants charged in finalised court appearances",
  "covid", ".", "Persons of interest proceeded against for a COVID-19 related breach of the Public Health Act 2010",
  "crime-statistics-by-lga", "pois", "Persons of interest proceeded against",
  "crime-statistics-by-lga", "victims", "Victims",
  "custody", "remand custody to sentenced custody", "{who} moving from remand to sentenced custody",
  "custody", "discharged from custody", "{who} discharged from custody",
  "custody", "received into custody", "{who} received into custody",
  "custody", "time spent in remand custody", "{who} leaving remand custody",
  "custody", ".", "{who} in custody",
  "domestic-violence", "alleged offenders", "Alleged offenders proceeded against for domestic violence related offences",
  "domestic-violence", "victims|relationship to the victim", "Victims of domestic violence related offences",
  "domestic-violence", "assault incidents", "Domestic violence related assault incidents",
  "domestic-violence", ".", "Domestic violence related incidents",
  "driving-offences", ".", "Driving offences with a person proceeded against",
  "drug-offences", "alleged offenders", "Alleged offenders proceeded against for use/possess drug incidents",
  "drug-offences", "court appearances", "Proven court appearances with a use/possess drugs principal offence",
  "drug-offences", ".", "Use/possess drug incidents",
  "seriousness-ranking", ".", "ANZSOC offence groups",
  "murder", ".", "Murder victims",
  "open-datasets", "murder victims", "Murder victims",
  "open-datasets", "graffiti offences", "Legal proceedings for graffiti offences",
  "open-datasets", "graffiti", "Graffiti incidents",
  "open-datasets", "non-fatal shooting", "Non-fatal shooting incidents",
  "open-datasets", "spiking", "Drink or food spiking incidents",
  "open-datasets", "offences against the person", "Incidents of selected offences against the person",
  "sexual-assault", "alleged offenders", "Alleged offenders proceeded against for sexual assault",
  "sexual-assault", "victims", "Victims of sexual assault incidents",
  "sexual-assault", ".", "Sexual assault incidents",
  "target-10", "in custody", "Aboriginal adults in custody",
  "target-10", "appearing in court", "Aboriginal adults appearing in court",
  "target-11", "in detention", "Aboriginal young people in detention",
  "target-11", "appearing in court", "Aboriginal young people appearing in court",
  "target-11", "court diversion", "Aboriginal young people proceeded against via a court diversion",
  "target-13", "domestic violence related assault", "Aboriginal child and adult female victims of domestic violence related assault",
  "target-13", ".", "Aboriginal child and adult female victims of selected offences",
  "weapons", "where a (firearm|knife\\*?) was", "Non-domestic assault, domestic assault and robbery incidents",
  "weapons", "selected violent incidents", "Selected violent incidents",
  "young-people", "estimated resident population", "Persons aged 10 to 17 years",
  "young-people", "either to court", "Young people proceeded against by police",
  "young-people", ".", "Young people proceeded against to court",
  "^nt-", "assault", "Assault offences",
  "^nt-", "population estimates", "Persons",
  "^nt-", ".", "Offences",
  "supplementary", "motor vehicles recovered", "Stolen motor vehicles",
  "bail-statistics", "youth justice unsentenced", "Youth Justice unsentenced receptions and discharges to bail",
  "re-offending", ".", "{reoffending}",
  "supplementary", ".", "{offences}",
  "^vic-", ".", "{vic}",
  ".", ".", "Criminal incidents")
proper <- function(x) {
  x <- str_replace_all(x, c("\\baboriginal\\b" = "Aboriginal", "\\btorres strait islander\\b" = "Torres Strait Islander", "\\brajac\\b" = "RAJAC", "\\bnsw\\b" = "NSW"))
  str_replace_all(x, "\\b(afm|oth|pin|lga)(?=s?\\b)", toupper)
}
# Victoria's Contents titles: "Number and rates (per 1,000 population) of family incidents
# involving an Aboriginal person by RAJAC, LGA, and role - January 2025 to December 2025"
vic_who <- function(key) {
  k <- str_remove(key, "^(number and )?rates \\(per [0-9,]+ population\\) of ")
  k <- str_remove(k, "\\s+-\\s+(january|july) [0-9]{4} to .*$") |> str_remove("\\s+\\(% of [^)]*\\)") |> str_remove("\\s+\\(and % [^)]*\\)")
  k <- str_remove(k, "\\s+(by|for the top|for previous|for the previous) .*$") |> str_remove("\\s+in the current year \\([0-9–-]+\\)$")
  k <- str_remove(k, "\\s+and rates? per [0-9,]+ population$") |> str_replace(" incident rates \\(per [0-9,]+ population\\)$", " incidents")
  k
}
subject <- function(pub, key) {
  r <- who_rules[which(map_lgl(seq_len(nrow(who_rules)), ~ str_detect(pub, who_rules$pub[.x]) && str_detect(key, who_rules$key[.x])))[1], ]
  pop <- r$population; extra <- list()
  if (str_detect(pop, "\\{who\\}")) pop <- str_replace(pop, "\\{who\\}", if (str_detect(key, "young people")) "Young people" else "Adults")
  if (pop == "{reoffending}") pop <- str_remove(str_remove(key, "^number of distinct "), ",? by (cumulative|whether).*$")
  if (pop == "{offences}") pop <- str_extract(key, "^.*? offences")
  if (pop == "{vic}") pop <- vic_who(key)
  pop <- proper(sentence(pop))
  if (str_detect(pub, "court-and-sentencing|custody") && str_detect(key, "^(\\. )?(characteristics of |time spent in remand custody for |summary characteristics of )?aboriginal ")) extra$indigenous_status <- ATSI
  if (str_detect(pub, "^act-")) extra$region <- str_to_title(str_remove(key, " - .*$"))
  if (str_detect(pub, "local-area-rankings")) extra$recorded_incident_offence <- sentence(str_remove(str_match(key, "^incidents of (.*?) as recorded")[, 2], "~$"))
  if (str_detect(pub, "weapons") && str_detect(key, "where a (firearm|knife)")) extra$weapon_type <- if (str_detect(key, "firearm")) "Firearm" else "Knife"
  if (str_detect(key, "^mean custodial sentence")) extra <- c(extra, list(measure = "Mean custodial sentence", unit = "months"))
  # Blocks of one sheet told apart only by their titles: NT regions ("Darwin Assault
  # Statistics"), custody by sex ("... for Aboriginal male adults"), court tables of
  # domestic violence offences
  if (pub == NT && !is.na(r <- str_match(key, "^(.*) (crime|assault) statistics$")[, 2]) && r != "northern territory") extra$region <- str_to_title(r)
  if (str_detect(pub, "custody") && str_detect(key, "\\b(male|female)\\b")) extra$sex <- if (str_detect(key, "\\bfemale\\b")) "Females" else "Males"
  if (str_detect(pub, "court-and-sentencing") && str_detect(key, "domestic violence")) extra$domestic_violence_status <- "Domestic violence related"
  # A title that names one measure ("... percent of incidents within offence category",
  # "Rate per 100,000 population of ..."); AJI's "(% of previous stage)"
  key <- str_remove_all(key, "[*^~]+")
  pct <- str_match(key, "\\(% of ([^)]*)\\)")[, 2]
  if (!is.na(pct)) extra <- c(extra, list(measure = paste("Proportion of", pct), unit = "%"))
  else if (str_detect(key, "percent(age)? of|proportion of") && !str_detect(key, "^number and|number(,| and) (percent|proportion)")) extra <- c(extra, list(measure = "Proportion", unit = "%"))
  else if (str_detect(key, "^(annual |monthly )?rates? (of .*?)?(per|\\(per)") && !is.null(u <- denominator(key))) extra <- c(extra, list(measure = "Rate", unit = u))
  c(list(population = pop), extra)
}
for (i in seq_len(nrow(titles))) ms$subjects[[titles$pub[i]]][[titles$key[i]]] <- subject(titles$pub[i], titles$key[i])
# Every record gets its state; untitled tables (Victoria, Queensland, WA, NSW data
# extracts) get the publication's population
default_population <- c(
  "nsw-bocsar-alcohol-related-violence" = "Criminal incidents", "nsw-bocsar-criminal-offences-data" = "Criminal incidents",
  "nsw-bocsar-daily-incident-data" = "Criminal incidents", "nsw-bocsar-trend-data-files" = "Criminal incidents",
  "nsw-bocsar-police-clear-up-rates" = "Criminal incidents", "nsw-bocsar-local-area-rankings" = "Criminal incidents",
  "qld-victim-numbers-police-region-monthly-from-jan-2001" = "Victims", "qld-victim-numbers-qld-monthly-from-jan-2001" = "Victims",
  "wa-wa-police-crime-time-series" = "Offences",
  "vic-crime-statistics-agency-data-tables-aboriginal-and-torres-strait-islander-victim-data" = "Victim reports",
  "vic-crime-statistics-agency-data-tables-aboriginal-and-torres-strait-islander-victim-data-by-lga" = "Victim reports",
  "vic-crime-statistics-agency-data-tables-alleged-offender-incidents" = "Alleged offender incidents",
  "vic-crime-statistics-agency-data-tables-bail-statistics" = "Bail decisions",
  "vic-crime-statistics-agency-data-tables-criminal-incidents" = "Criminal incidents",
  "vic-crime-statistics-agency-data-tables-family-incidents" = "Family incidents",
  "vic-crime-statistics-agency-data-tables-harm-caused" = "Victim reports",
  "vic-crime-statistics-agency-data-tables-indigenous-alleged-offender-incidents" = "Alleged offender incidents",
  "vic-crime-statistics-agency-data-tables-indigenous-family-incidents" = "Family incidents",
  "vic-crime-statistics-agency-data-tables-indigenous-unique-alleged-offenders" = "Unique alleged offenders",
  "vic-crime-statistics-agency-data-tables-indigenous-unique-victim-reports" = "Unique victims",
  "vic-crime-statistics-agency-data-tables-recorded-offences" = "Offences",
  "vic-crime-statistics-agency-data-tables-unique-alleged-offenders" = "Unique alleged offenders",
  "vic-crime-statistics-agency-data-tables-unique-victims" = "Unique victims",
  "vic-crime-statistics-agency-data-tables-victim-reports" = "Victim reports")
for (p in PUBS) {
  ms$publication_title_flags[[p]] <- list(list(pattern = "^", set = c(list(state = state_of(p)), if (!is.na(default_population[p])) list(population = default_population[[p]]))))
  ms$default_measure[[p]] <- "Number"
}

# One spelling per label: state labels that differ only by case, spacing, punctuation or a
# footnote marker ("Greater Sydney*", "Far West And Orana", "FLYNN") take the earlier
# publications' spelling where they have exactly one, else the plainest common spelling
# (no marker, not all capitals, then the most used). Labels the earlier publications use are
# never mapped, so they don't change; nor are the labels this seed splits (periods, measures,
# units, who is counted). The earlier publications' labels are read from the last build's
# integrated/series/ files
fold <- function(x) trimws(gsub("[^a-z0-9%$<>+]+", " ", gsub("&", " and ", tolower(x), fixed = TRUE)))  # as labels_have_one_spelling
earlier <- list.files("integrated/series", "\\.csv$", full.names = TRUE)
earlier <- earlier[!str_detect(basename(earlier), "^(act|nsw|nt|qld|sa|tas|vic|wa)-")]
if (!length(earlier)) stop("No integrated/series/ files for the earlier publications: run tar_make() first")
earlier <- map(earlier, ~ data.table::fread(.x, colClasses = "character", na.strings = ""))
state_labels <- bind_rows(map(sheets, "labs")) |> group_by(dim, label) |> summarise(n = sum(n), .groups = "drop")
split_dims <- c(FIELDS, "population", "counted_entity", "measure", "unit")
mapped <- 0L
for (d in setdiff(unique(state_labels$dim), split_dims)) {
  l <- state_labels[state_labels$dim == d, ]; nat <- unique(na.omit(unlist(map(earlier, ~ .x[[d]])))); nat_fold <- fold(nat)
  keys <- c(names(hs$split[[d]]), unlist(map(hs$publication_split, ~ names(.x[[d]]))))  # labels a split reads
  for (g in split(seq_len(nrow(l)), fold(l$label))) {
    nat_g <- nat[nat_fold == fold(l$label[g[1]])]
    if (length(g) < 2 && !length(nat_g)) next
    if (length(nat_g) > 1 || any(c(l$label[g], nat_g) %in% keys)) next  # several earlier spellings, or a label a split reads
    plain <- l[g, ] |> mutate(marker = str_detect(label, "[*^~#]+$"), caps = label == toupper(label) & str_detect(label, "[A-Z]{4}")) |> arrange(marker, caps, -n, label)
    to <- if (length(nat_g)) nat_g else plain$label[1]
    for (from in setdiff(l$label[g], c(to, nat))) { ns$values[[d]][[from]] <- to; mapped <- mapped + 1L }
  }
}
cat("one spelling: mapped", mapped, "state labels\n")

# Values: BOCSAR's symbols, as its workbooks' notes define them. "nc" (and "nc**", with a
# footnote marker): not calculated, because a 12-month period had fewer than 20 incidents
# or the LGA has fewer than 3,000 people. "1 to 4": a count between 1 and 4, suppressed for
# privacy. "Stable": no significant trend. A significant trend is a number: "Up 4.2%" is
# 4.2 and "Down 4.2%" is -4.2. So are clear-up rate changes ("1.9 p.p") and Closing the Gap
# rate ratios ("11.1x"). The offence seriousness ranking's one "." has no ranking
vs <- rd("integration/value_spec.json")
bocsar <- c("nc" = "not_calculated", "nc**" = "not_calculated", "n.c." = "not_calculated", "n.c" = "not_calculated",
            "1 to 4" = "not_published", "Stable" = "no_significant_trend", "stable" = "no_significant_trend")
for (p in grep("^nsw-bocsar-", PUBS, value = TRUE)) for (t in names(bocsar)) vs$symbols[[p]][[t]] <- list(status = bocsar[[t]])
vs$symbols[[RANK]][["."]] <- list(status = "not_available")
num <- "(-?[0-9]+(?:\\.[0-9]+)?)"
vs$rewrites <- list(
  list(pattern = "^Up ([0-9]+(?:\\.[0-9]+)?)%$", replacement = "\\1", description = "BOCSAR trend: significant rise, average annual percentage change (Up 4.2% is 4.2)"),
  list(pattern = "^Down ([0-9]+(?:\\.[0-9]+)?)%$", replacement = "-\\1", description = "BOCSAR trend: significant fall (Down 4.2% is -4.2)"),
  list(pattern = paste0("^", num, " ?p\\.p\\.?$"), replacement = "\\1", description = "BOCSAR clear-up rates: change in percentage points (1.9 p.p)"),
  list(pattern = paste0("^", num, "x$"), replacement = "\\1", description = "BOCSAR Closing the Gap: rate ratio (11.1x)"))

wr(ns, "normalisation/normalisation_spec.json"); wr(hs, "harmonisation/harmonisation_spec.json"); wr(ms, "measures/measure_spec.json"); wr(vs, "integration/value_spec.json")
cat("publications:", length(PUBS), "| subjects:", sum(lengths(ms$subjects[PUBS])), "| publication splits:", sum(unlist(map(hs$publication_split[PUBS], lengths))), "\n")
if (length(unmapped)) cat("Measure headings left as published:\n", paste0("  ", unmapped, collapse = "\n"), "\n")
