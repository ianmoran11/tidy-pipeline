# Spec entries for the sheets admitted on 2026-11-02: AIHW Child protection (2021-22 to
# 2024-25, and the rewritten 2020-21 recipes), AIHW Youth Justice 2024-25 and Report on
# Government Services Justice 2020-2026 (ISSUES.md I1, I2, I25).
# Rerunnable: it sets only its own entries, so run it after seed_label_consistency.R,
# which rewrites the live specs from consistency_baseline/.
# Usage: Rscript orchestrator/qa/seeds/seed_aihw_rogs_specs.R
# Writes:
#   normalisation: one name for concepts the agents named twice; period spellings; the RoGS
#     confidence-interval note as estimate_type
#   harmonisation: period_type for multi-year ranges; reference dates; a unit fix for
#     "Estimate ('000)"
#   measures: a subject pattern for AIHW table numbers (S5.12, T2.2); a subject for every
#     title; title flags for Youth Justice rate and day tables; Youth Justice counts by default
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(rlang); library(unpivotr)})
rd <- function(p) jsonlite::read_json(p); wr <- function(x, p) jsonlite::write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null")
ns <- rd("normalisation/normalisation_spec.json"); hs <- rd("harmonisation/harmonisation_spec.json"); ms <- rd("measures/measure_spec.json")
CP <- "aihw-child-protection-australia"; YJ <- "aihw-youth-justice-australia"; RG <- "pc-report-on-government-services-justice"

# Normalisation: names ---------------------------------------------------------------
# One concept, two names from different agents (never in the same recipe)
same_name <- c(rate_basis = "rate_standardisation", rate_adjustment = "rate_standardisation", custody_type = "prison_security",
  prison_facility_type = "custodial_facility_type", assault_type = "assault_severity", police_staff_deployment = "police_staff_function",
  property_entry_type = "unlawful_entry_type", language_requested = "interpreter_language", language_group = "interpreter_language_group",
  education_program = "education_type", expenditure_item = "expenditure_type", detention_legal_status = "legal_status")
for (n in names(same_name)) ns$dimension_names[[n]] <- same_name[[n]]

# AIHW labels use non-breaking spaces ("Per cent"), which \s doesn't match
for (i in seq_along(ns$clean)) if (identical(ns$clean[[i]]$pattern, "\\s+")) ns$clean[[i]]$pattern <- "[\\s\\x{00A0}]+"
ns$values$measure[["Percentage"]] <- "Proportion"
# RoGS footnote markers followed by a comma ("Vic (d),", "Per 100,000 people (g), (h),") or
# combined ("NSW(a,b)"). No label elsewhere ends like this
markers <- "(?:\\s*\\(\\s*[a-z]{1,2}(?:\\s*,\\s*[a-z]{1,2})+\\s*\\)|\\s*\\(\\s*(?:[a-z]{1,2}|[0-9]{1,2})\\s*\\)\\s*,)+\\s*$"
if (!markers %in% map_chr(ns$clean, "pattern")) ns$clean <- c(ns$clean, list(list(pattern = markers, replace = "")))
# Publisher typos in AIHW state headings
for (s in list(c("VIC", "Vic."), c("Tas€", "Tas."), c("WA)b)", "WA"), c("Tas(g)(h)(I)", "Tas."), c("ACT(C)", "ACT"), c("Totals", "Total"))) ns$values$state[[s[1]]] <- s[2]

# The group 1 sheets, normalised with the names above
for (f in c("R/field_sets.R", "R/published_value.R", "R/expand_excel_range.R", "R/one_enhead.R", "R/blank_value_cells.R", "R/process_recipe.R", "R/normalise.R")) source(f)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c", reference_only = "l", sheet_index = "i"), na = c("", "NA"), trim_ws = FALSE)
m <- filter(m, publication_id %in% c(CP, YJ, RG), !reference_only, file.exists(file.path("tidy-recipes", paste0(sheet_sha256, ".json"))))
sheets <- parallel::mclapply(seq_len(nrow(m)), function(i) tryCatch(normalise(process_recipe(m[i, ], file.path("tidy-recipes", paste0(m$sheet_sha256[i], ".json"))), ns),
                                                                   error = function(e) NULL), mc.cores = 6)
labels <- function(field) unique(unlist(map(sheets, function(s) map(s$tables, function(t) c(t$meta_data_list[[field]], map(t$tidy_table_list, field))))))

# Normalisation: period spellings seen in these sheets. Financial years and ranges take an
# en dash; ISO dates from date-formatted headings become "30 June 2025"
spell <- c("^([0-9]{4})-([0-9]{2})(?: \\(e\\),)?$" = "\\1–\\2", "^([0-9]{4})-([0-9]{2}) to ([0-9]{4})-([0-9]{2})$" = "\\1–\\2 to \\3–\\4",
           "^([0-9]{4})-06-30$" = "30 June \\1")
for (l in labels("period")) for (p in names(spell)) if (str_detect(l, p) && is.null(ns$values$period[[l]])) {
  to <- str_replace(l, p, spell[[p]]); ns$values$period[[l]] <- ns$values$period[[to]] %||% to  # normalise() maps once, so follow an existing entry
}

# The RoGS notes explaining the unlabelled interval columns (layouts.md)
for (l in grep("confidence interval", labels("estimate_type"), value = TRUE, ignore.case = TRUE)) ns$values$estimate_type[[l]] <- "95% confidence interval"

# Harmonisation ----------------------------------------------------------------------
# The RoGS 2025 police "Estimate ('000)" row says "no." in its unit column
hs$split$measure[["Estimate ('000)"]][["_replace"]] <- list("unit")
# RoGS writes an age-standardised rate's unit as "rate (AS)"
hs$split$unit[["rate (AS)"]] <- list(unit = "rate", rate_standardisation = "Age standardised")
# Ranges are a change or total over a window, not the single year they end in
for (p in unique(unlist(ns$values$period))) if (str_detect(p, "^[0-9]{4}–[0-9]{2} to [0-9]{4}–[0-9]{2}$")) {
  first <- as.integer(str_sub(p, 1, 4)); last <- as.integer(str_sub(p, -7, -4))
  hs$split$period[[p]] <- list(period_type = sprintf("Range of %d years", last - first + 1))
  hs$reference_dates$default[[p]] <- hs$reference_dates$default[[p]] %||% sprintf("%d-06-30", last + 1)
}
# Plain years: 30 June in child protection (as before), calendar years in RoGS (police
# tables from ABS Recorded Crime – Victims)
for (y in 2000:2030) {
  hs$reference_dates[[CP]][[as.character(y)]] <- sprintf("%d-06-30", y)
  hs$reference_dates[[RG]][[as.character(y)]] <- sprintf("%d-12-31", y)
  hs$reference_dates$default[[sprintf("30 June %d", y)]] <- hs$reference_dates$default[[sprintf("30 June %d", y)]] %||% sprintf("%d-06-30", y)
}

# Measures ---------------------------------------------------------------------------
# AIHW numbers tables "Table 4.14:", "Table S5.12:" or just "T2.2:"
ms$subject_pattern <- "^(?:FDV\\s+|ANZSOC 2023\\s+)?(?:Table\\s*[A-Z]{0,3}\\s*[0-9]+(?:\\.[0-9]+)*(?-i:[a-z])?\\s*[:.–-]?\\s*|(?-i:[A-Z]){1,2}[0-9]+(?:\\.[0-9]+)*(?-i:[a-z])?:\\s*)?(?:Experimental data(?:\\s*\\([a-z0-9]{1,2}\\))?\\s*[–-]\\s*)?([^,]+)"
key_of <- function(cells) {
  t <- str_squish(gsub(" ", " ", paste(cells, collapse = " ")))
  str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(coalesce(str_match(t, regex(ms$subject_pattern, ignore_case = TRUE))[, 2], ""))))
}
titles <- bind_rows(map(sheets, function(s) {
  if (is.null(s)) return(NULL)
  own <- unlist(s$sheet_metata[["table_title"]])
  map_dfr(s$tables, function(t) tibble(pub = s$source$publication_id, key = key_of(if (length(own)) own else unlist(t$meta_data_list[["table_title"]]))))
})) |> distinct() |> filter(key != "")

sentence <- function(x) {
  y <- paste0(str_to_upper(substr(x, 1, 1)), substring(x, 2))
  y <- str_replace_all(y, regex("aboriginal and torres strait islander", ignore_case = TRUE), "Aboriginal and Torres Strait Islander")
  str_replace_all(y, "\\bindigenous\\b", "Indigenous")
}
# AIHW titles name who is counted before "by ...": "children in out-of-home care by age"
aihw_subject <- function(key) {
  if (str_detect(key, "^population of ")) return(list(population = sentence(str_remove(key, "^population of ")), measure = "Population"))
  if (str_detect(key, "^average length of time")) {
    who <- str_match(key, "spent (.*?)(?: by .*)?$")[, 2]
    return(list(population = sentence(paste("young people", who)), measure = "Average length of time"))
  }
  p <- str_remove(key, "\\s+by\\s.*$") |> str_remove("^(number of|all) ") |> str_replace_all("(?<=[a-z])–(?=[a-z])", "-")
  list(population = sentence(p))
}
fixed <- list(
  "national child protection trend data" = list(population = "Children in the child protection system"),
  "young people by number of completed supervision periods" = list(population = "Young people under supervision"),
  "young people by indigenous status and number of community-based supervised orders" = list(population = "Young people with community-based supervised orders"),
  "young people by indigenous status and number of detention orders" = list(population = "Young people with detention orders"),
  "young people by indigenous status and number of supervised orders" = list(population = "Young people with supervised orders"))
for (i in which(titles$pub %in% c(CP, YJ))) ms$subjects[[titles$pub[i]]][[titles$key[i]]] <- fixed[[titles$key[i]]] %||% aihw_subject(titles$key[i])
# Youth Justice tables are counts unless the title ends "(rate)" (per 10,000 young people)
# or "(days)", or names what is counted after a colon ("…, 2024–25: Number of releases").
# Child protection populations "as at 31 December" are a separate series from those at
# 30 June (the year labels are the same)
ms$default_measure[[YJ]] <- "Number"
tail <- function(text) sprintf("^Table S[0-9]+[a-z]?:.*: %s\\.?\\s*(/|$)", text)
flags <- list(list(pattern = "^Table S[0-9]+[a-z]?:.*\\(rate\\)(\\s*\\([a-z]\\))*\\s*(/|$)", set = list(measure = "Rate", unit = "per 10,000")),
              list(pattern = "^Table S[0-9]+[a-z]?:.*\\(days\\)(\\s*\\([a-z]\\))*\\s*(/|$)", set = list(unit = "days")),
              list(pattern = tail("(Number of receptions|Receptions)"), set = list(measure = "Number of receptions")),
              list(pattern = tail("(Number of releases|Releases)"), set = list(measure = "Number of releases")),
              list(pattern = tail("Number of young people during the year"), set = list(measure = "Number of young people")),
              list(pattern = "^Table P[0-9]+: Population of children.*31 December", set = list(scope = "At 31 December")),
              list(pattern = "^(Table )?[A-Z]{0,2}[0-9]+(\\.[0-9]+)*[a-z]?:.*\\(number\\)(\\s*\\([a-z]\\))*\\s*(/|$)", set = list(measure = "Number")),
              list(pattern = "^(Table )?[A-Z]{0,2}[0-9]+(\\.[0-9]+)*[a-z]?:.*\\(per cent\\)(\\s*\\([a-z]\\))*\\s*(/|$)", set = list(measure = "Proportion", unit = "%")),
              list(pattern = "^Table S[0-9]+[a-z]?:.*by .*age at first supervision", set = list(age_basis = "Age at first supervision")),
              list(pattern = "^Table S[0-9]+[a-z]?:.*by .*age at first detention", set = list(age_basis = "Age at first detention")))
# Units and measures the RoGS unit column and the AIHW data-type column imply
ms$measure_from_unit[["rate"]] <- "Rate"; ms$measure_from_unit[["Index"]] <- "Index"
for (m in c("Number per 1,000", "Rate per 1,000 children")) ms$unit_from_measure[[m]] <- "per 1,000"
ms$unit_from_measure[["Population"]] <- "no."
ms$title_flags <- c(Filter(function(f) !f$pattern %in% map_chr(flags, "pattern"), ms$title_flags), flags)

# RoGS titles name an indicator, so each gets who is counted and the measure by hand
survey <- "Persons aged 15 years and over"
rogs <- tibble::tribble(
  ~key, ~population, ~measure, ~scope,
  "backlog indicator", "Pending court cases", "Backlog indicator", NA,
  "on-time case processing indicator", "Finalised court cases", "On-time case processing indicator", NA,
  "lodgments", "Court lodgments", NA, NA,
  "finalisations", "Court finalisations", NA, NA,
  "criminal lodgments and finalisations", "Criminal court cases", NA, NA,
  "clearance indicator – finalisations/lodgments", "Court cases", "Clearance indicator", NA,
  "clearance indicator - finalisations/lodgments", "Court cases", "Clearance indicator", NA,
  "clearance indicator – all matters", "Court cases", "Clearance indicator", "All matters",
  "clearance indicator - all matters", "Court cases", "Clearance indicator", "All matters",
  "attendance indicator (average number of attendances per finalisation)", "Court finalisations", "Average attendances per finalisation", NA,
  "judicial officers (fte and number per 100 000 people)", "Judicial officers", NA, NA,
  "judicial officers (fte and number per 100", "Judicial officers", NA, NA,
  "judicial officers per 1000 finalisations", "Judicial officers", "Judicial officers per 1,000 finalisations", NA,
  "judicial officers per 1", "Judicial officers", "Judicial officers per 1,000 finalisations", NA,
  "full-time equivalent (fte) staff per 1", "Court staff", "FTE staff per 1,000 finalisations", NA,
  "full time equivalent (fte) staff per 1000 finalisations", "Court staff", "FTE staff per 1,000 finalisations", NA,
  "real net recurrent expenditure per finalisation", "Courts", "Real net recurrent expenditure per finalisation", NA,
  "real recurrent expenditure", "Courts", "Real recurrent expenditure", NA,
  "real net recurrent expenditure", "Courts", "Real net recurrent expenditure", NA,
  "real recurrent expenditure per finalisation: civil", "Civil courts", "Real recurrent expenditure per finalisation", NA,
  "real recurrent expenditure per finalisation: criminal", "Criminal courts", "Real recurrent expenditure per finalisation", NA,
  "real income (excluding fines)", "Courts", "Real income (excluding fines)", NA,
  "real average civil court fees paid per lodgment", "Civil courts", "Real average court fees paid per lodgment", NA,
  "court fee relief (waivers and reductions)", "Civil courts", "Court fee relief", NA,
  "cost recovery – civil court fees collected as a proportion of civil expenditure excluding payroll tax", "Civil courts", "Cost recovery", NA,
  "cost recovery - civil court fees collected as a proportion of civil expenditure excluding payroll tax", "Civil courts", "Cost recovery", NA,
  "proportion of total payable civil court fees that were waived or reduced", "Civil courts", "Proportion of payable fees waived or reduced", NA,
  "proportion of total payable civil court fees which were waived or reduced", "Civil courts", "Proportion of payable fees waived or reduced", NA,
  "case study data - booking requests for interpreters in the courtroom (criminal): by language requested", "Interpreter booking requests", NA, "Criminal courts",
  "case study data – booking requests for interpreters in the courtroom (criminal): by language requested", "Interpreter booking requests", NA, "Criminal courts",
  "finalised civil cases in the magistrates' court involving a finalised application for a domestic or family violence related protection order", "Finalised civil cases with a family violence protection order application", NA, "Magistrates' courts",
  "complaints", "Complaints about courts", NA, NA,
  "magistrates' court decisions resulting in a guilty outcome for defendants", "Defendants with a guilty outcome", NA, "Magistrates' courts",
  "magistrates court adjudicated defendants who submitted a guilty plea or were found guilty", "Adjudicated defendants with a guilty plea or found guilty", NA, "Magistrates' courts",
  "perceptions of safety", survey, "Perceptions of safety", NA,
  "perceptions of safety (before 2023-24)", survey, "Perceptions of safety", "Survey before 2023–24",
  "police integrity", survey, "Opinions on police integrity", NA,
  "police integrity (before 2023-24)", survey, "Opinions on police integrity", "Survey before 2023–24",
  "satisfaction with services provided by the police", survey, "Satisfaction with police services", NA,
  "satisfaction with services provided by the police (before 2023-24)", survey, "Satisfaction with police services", "Survey before 2023–24",
  "road safety", survey, "Road safety behaviour", NA,
  "road safety (before 2023-24)", survey, "Road safety behaviour", "Survey before 2023–24",
  "perceptions of crime problems", survey, "Perceptions of crime problems", NA,
  "perceptions of crime problems (before 2023-24)", survey, "Perceptions of crime problems", "Survey before 2023–24",
  "feelings of safety", survey, "Feelings of safety", NA,
  "feelings of safety in the last 12 months", survey, "Feelings of safety in the last 12 months", NA,
  "outcome of investigation at 30 days", "Victims", NA, NA,
  "estimated victims of selected property crimes", "Victims of selected property crimes", NA, NA,
  "estimated victims of selected personal crimes", "Victims of selected personal crimes", NA, NA,
  "reporting rates", "Victims of selected personal crimes", "Reporting rate", NA,
  "victims of recorded crime", "Victims", NA, NA,
  "recorded victims of sexual assault", "Victims of sexual assault", NA, NA,
  "recorded victims of family and domestic violence related offences", "Victims of family and domestic violence related offences", NA, NA,
  "police staffing", "Police staff", NA, NA,
  "police services expenditure", "Police services", "Expenditure", NA,
  "deaths in police custody", "Deaths in police custody", NA, NA,
  "youth diversions as a proportion of offenders", "Young offenders", "Youth diversions as a proportion of offenders", NA,
  "trends in complaints", "Complaints about police", NA, NA,
  "road deaths", "Road deaths", NA, NA,
  "traffic accident hospitalisations", "Traffic accident hospitalisations", NA, NA,
  "community corrections offender population (average daily number) and rates per 100", "Community corrections offenders", NA, NA,
  "prisoner population (average daily number) and rates per 100", "Prisoners", NA, NA,
  "imprisonment and community corrections population rate per 100", "Prisoners and community corrections offenders", NA, NA,
  "escapes", "Prisoners", "Escapes", NA,
  "prison capacity utilisation", "Prisons", "Capacity utilisation", NA,
  "community work (per cent of imposed hours unpaid community work acquitted)", "Community work orders", "Proportion of imposed hours acquitted", NA)
for (i in seq_len(nrow(rogs))) {
  e <- as.list(rogs[i, c("population", "measure", "scope")]); ms$subjects[[RG]][[rogs$key[i]]] <- e[!is.na(unlist(e))]
}
missing <- setdiff(titles$key[titles$pub == RG], names(ms$subjects[[RG]]))
if (length(missing)) message("RoGS titles without a subject: ", paste(missing, collapse = " | "))

wr(ns, "normalisation/normalisation_spec.json"); wr(hs, "harmonisation/harmonisation_spec.json"); wr(ms, "measures/measure_spec.json")
cat("subjects:", sum(lengths(ms$subjects[c(CP, YJ, RG)])), "| estimate_type notes:", sum(grepl("confidence", names(ns$values$estimate_type))),
    "| ranges:", sum(grepl(" to ", names(hs$split$period))), "\n")
