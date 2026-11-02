# The hand-written tables for seed_label_consistency.R. Each entry is a judgement that can
# be changed here and reseeded.

# Columns for one concept. Those not in the dictionary's `use` list are the ones ISSUES.md
# I10 lists as likely merges, with every label shared; the rest only become snake_case.
renames <- list(
  duration = "case_duration", fine_value_band = "fine_amount",
  weekly_cash_earnings_band = "weekly_total_cash_earnings_band",
  defendant_rate_basis = "rate_standardisation", defendant_rate_type = "rate_standardisation", offender_rate_basis = "rate_standardisation",
  Duration = "supervision_duration", Households = "households", `order outcome` = "order_outcome", Relationship = "carer_relationship",
  Supervision = "supervision_history", `Supervision periods` = "supervision_periods", `Summary characteristics` = "federal_defendant_summary_item")

same_as <- list(
  measure = c(
    "Proportion (%)" = "Proportion", "PROPORTION(%)" = "Proportion", "PROPORTION %" = "Proportion", "PROPORTIONS (%)" = "Proportion",
    "Percent" = "Proportion", "Per cent" = "Proportion", "%" = "Proportion",
    "no." = "Number", "No." = "Number", "no" = "Number",
    "OFFENDER RATE" = "Offender rate", "Offender Rate" = "Offender rate", "Imprisonment Rate" = "Imprisonment rate",
    "Victmisation rate" = "Victimisation rate", "Victimimisation rate" = "Victimisation rate", "Vicimisation rate" = "Victimisation rate", "Victimsation rate" = "Victimisation rate",
    "PERCENTAGE CHANGE (%)" = "Percentage change", "Percentage change (%)" = "Percentage change", "Percentage Change (%)" = "Percentage change",
    "% CHANGE (FROM PRECEDING YEAR)" = "Percentage change", "% CHANGE (FROM PREVIOUS YEAR)" = "Percentage change", "% CHANGE IN NUMBERS" = "Percentage change",
    "Mean Age" = "Mean age", "MEAN AGE" = "Mean age", "mean age" = "Mean age", "Mean age (years)" = "Mean age",
    "Median Age" = "Median age", "Median age (years)" = "Median age", "rate" = "Rate", "90th Percentile" = "90th percentile",
    # Survey column headings. "PERSONS" beside "PROPORTION" is a count: in thousands, or its
    # RSE in an RSE table, where % is the unit of the RSE
    "Persons" = "Number", "Households" = "Number", "Estimates" = "Number", "Persons/households" = "Number", "All persons/households" = "Number",
    "All persons/ households" = "Number", "Households - counts" = "Number", "Household - counts" = "Number", "Households - percents" = "Proportion"),
  unit = c("MONTHS" = "months", "YEARS" = "years", "000" = "'000", "PERIODIC DETAINEE WEEKS" = "periodic detainee weeks", "DETAINEE WEEKS" = "detainee weeks"),
  state = c("VIC." = "Vic.", "TAS." = "Tas.", "AUST." = "Australia",
    "ACT IN ACT" = "ACT in ACT", "AUSTRALIAN CAPITAL TERRITORY (Prisoners held in ACT)" = "ACT in ACT", "AUSTRALIAN CAPITAL TERRITORY (Prisoners held in ACT))" = "ACT in ACT",
    "PRISONERS IN AUSTRALIAN CAPITAL TERRITORY PRISONS" = "ACT in ACT", "AUSTRALIAN CAPITAL TERRITORY (EXCLUDING PRISONERS HELD IN NSW PRISONS)" = "ACT in ACT",
    "AUSTRALIAN CAPITAL TERRITORY (EXCLUDING ACT PRISONERS HELD IN NSW PRISONS)" = "ACT in ACT",
    "ACT IN NSW" = "ACT in NSW", "AUSTRALIAN CAPITAL TERRITORY (Prisoners held in NSW prisons)" = "ACT in NSW", "AUSTRALIAN CAPITAL TERRITORY PRISONERS HELD IN NSW PRISONS" = "ACT in NSW",
    "AUSTRALIAN CAPITAL TERRITORY (Sentenced Prisoners in New South Wales Prisons)" = "ACT in NSW", "AUSTRALIAN CAPITAL TERRITORY (Sentenced prisoners in New South Wales prisons)" = "ACT in NSW",
    "AUSTRALIAN CAPITAL TERRITORY (Sentenced prisoners in NSW prisons)" = "ACT in NSW", "AUSTRALIAN CAPITAL TERRITORY (SENTENCED PRISONERS IN NSW PRISONS)" = "ACT in NSW",
    "AUSTRALIAN CAPITAL TERRITORY (prisoners in NSW prisons)" = "ACT in NSW", "AUSTRALIAN CAPITAL TERRITORY (PRISONERS IN NSW PRISONS)" = "ACT in NSW",
    "AUSTRALIAN CAPITAL TERRITORY (Prisoners in NSW prisons)" = "ACT in NSW",
    "ACT Total" = "ACT total", "ACT TOTAL" = "ACT total", "AUSTRALIAN CAPITAL TERRITORY TOTAL" = "ACT total", "AUSTRALIAN CAPITAL TERRITORY (Total)" = "ACT total",
    "AUSTRALIAN CAPITAL TERRITORY (TOTAL)" = "ACT total"),
  court_level = c("MAGISTRATES' AND CHILDREN'S COURTS" = "Magistrates' and Children's Courts", "Magistrates' courts" = "Magistrates' Courts", "MAGISTRATES'" = "Magistrates' Courts",
    "Children's Court" = "Children's Courts", "CHILDREN'S" = "Children's Courts", "Childrens" = "Children's Courts", "HIGHER" = "Higher Courts", "Higher Court" = "Higher Courts",
    "Supreme court" = "Supreme Court", "Supreme" = "Supreme Court", "Intermediate court" = "Intermediate Court", "LOWER COURTS" = "Lower Courts", "Lower Court" = "Lower Courts",
    "OTHER COURTS" = "Other Courts", "Total Courts" = "All Courts"),
  sex = c("Organisation" = "Organisations", "Unknowns" = "Unknown"),
  indigenous_status = c("INDIGENOUS" = "Aboriginal and Torres Strait Islander", "Non- Indigenous" = "Non-Indigenous", "Unknown/ Not stated" = "Unknown/Not stated",
    "Non-Indigenous/Not stated" = "Non-Indigenous and Not stated", "Non-Indigenous and not stated" = "Non-Indigenous and Not stated"),
  disability_status = c("Has disability or restrictive condition" = "Has a disability or restrictive condition",
    "Does not have disability or restrictive condition" = "Does not have a disability or restrictive condition", "Not Stated" = "Not stated", "No Disability" = "No disability"),
  rate_standardisation = c("Age-standardised" = "Age standardised", "Crude rate" = "Crude", "Age standardised rate" = "Age standardised"),
  population = c("Federal defendants with guilty outcome" = "Federal defendants with a guilty outcome", "Victims of FDV" = "Victims of family and domestic violence",
    "Persons aged 15 or more" = "Persons aged 15 years and over", "Finalised defendants" = "Defendants finalised", "Organisation" = "Organisations",
    "Victim of face-to-face threatened assault" = "Victims of face-to-face threatened assault", "Victim of physical assault" = "Victims of physical assault",
    "Victim of threatened assault" = "Victims of threatened assault", "Victim of robbery" = "Victims of robbery", "Victim of sexual assault" = "Victims of sexual assault"),
  principal_offence = c("Offences against justice procedures," = "Offences against justice procedures"))

# Labels left as spelled because spelling is all that separates two quantities. Filled in
# from staging; a merge that adds indistinguishable values goes here until the tables differ.
unsafe <- tibble::tribble(~dim, ~label,
  # Youth Justice tables have no titles yet (ISSUES.md I25), so these spellings tell S7, S19 and S22 apart
  "age_group", "14-17 years", "age_group", "10-13 years",
  "remoteness_area", "Major Cities of Australia", "remoteness_area", "Inner Regional Australia", "remoteness_area", "Outer Regional Australia", "remoteness_area", "Very Remote Australia")

stat <- function(d, l, measure, unit = NULL, to = "Total") { e <- list(measure = measure); if (!is.null(unit)) e$unit <- unit; e[d] <- list(to); e[["_replace"]] <- list("measure", "unit"); e }
fixed_splits <- list(
  measure = list(
    # Column headings that say whether those counted were victims
    Victims = list(victimisation_status = "Victim", measure = "Number"), Victim = list(victimisation_status = "Victim", measure = "Number"),
    `Non-victims` = list(victimisation_status = "Non-victim", measure = "Number"), `Non-Victims` = list(victimisation_status = "Non-victim", measure = "Number"),
    `All persons` = list(victimisation_status = "Total", measure = "Number"), `All households` = list(victimisation_status = "Total", measure = "Number"),
    # This sheet has no unit row: see title_units
    `RSE of persons` = list(measure = "Number", estimate_type = "Relative standard error", unit = "%", `_replace` = list("estimate_type")),
    `RSE of percents` = list(measure = "Proportion", estimate_type = "Relative standard error", unit = "%", `_replace` = list("estimate_type")),
    Percents = list(measure = "Proportion", unit = "%"),
    `'000` = list(measure = NULL, unit = "'000"), `Estimate ('000)` = list(measure = NULL, unit = "'000"),
    `2006–07 NUMBER (no.)` = list(measure = NULL), `2007–08 NUMBER (no.)` = list(measure = NULL), `2006–07 PROPORTION (%)` = list(measure = NULL), `2007–08 PROPORTION (%)` = list(measure = NULL)),
  period = list(
    `2006–07 NUMBER (no.)` = list(period = "2006–07", measure = "Number", unit = "no.", `_replace` = list("measure", "unit")),
    `2007–08 NUMBER (no.)` = list(period = "2007–08", measure = "Number", unit = "no.", `_replace` = list("measure", "unit")),
    `2006–07 PROPORTION (%)` = list(period = "2006–07", measure = "Proportion", unit = "%", `_replace` = list("measure", "unit")),
    `2007–08 PROPORTION (%)` = list(period = "2007–08", measure = "Proportion", unit = "%", `_replace` = list("measure", "unit"))),
  age_group = list(`Mean age (youth)` = stat("age_group", "", "Mean age", "years"), `Median age (youth)` = stat("age_group", "", "Median age", "years")),
  indigenous_status = list(`Mean (years)` = stat("indigenous_status", "", "Mean age", "years"), `Median (years)` = stat("indigenous_status", "", "Median age", "years")),
  time_on_remand = list(`90th percentile (months)` = stat("time_on_remand", "", "90th percentile time on remand", "months"),
                        `90th Percentile (months)` = stat("time_on_remand", "", "90th percentile time on remand", "months")),
  # measure stays: it says what changed (Number, Imprisonment rate)
  change_measure = list(`% CHANGE (FROM PREVIOUS YEAR)` = list(change_measure = "Percentage change from previous year", unit = "%", `_replace` = list("unit")),
                        `% change (from previous year)` = list(change_measure = "Percentage change from previous year", unit = "%", `_replace` = list("unit"))),
  comparison_basis = list(`PERCENTAGE CHANGE (%)` = list(comparison_basis = "Percentage change", unit = "%", `_replace` = list("unit"))),
  measure_transformation = list(`PERCENTAGE CHANGE (%)` = list(measure_transformation = "Percentage change", unit = "%", `_replace` = list("unit"))),
  indicator = list(`Ratio - offences per defendant` = stat("indicator", "", "Offences per defendant", to = NULL)),
  federal_defendant_summary_item = list(`Ratio - offences per defendant` = stat("federal_defendant_summary_item", "", "Offences per defendant", to = NULL),
    `Mean (years)` = stat("federal_defendant_summary_item", "", "Mean age", "years", to = NULL), `Median (years)` = stat("federal_defendant_summary_item", "", "Median age", "years", to = NULL),
    `Mean (weeks)` = stat("federal_defendant_summary_item", "", "Mean case duration", "weeks", to = NULL), `Median (weeks)` = stat("federal_defendant_summary_item", "", "Median case duration", "weeks", to = NULL)))

unit_from_measure <- list(Number = "no.", Proportion = "%", `Percentage change` = "%", `Mean age` = "years", `Median age` = "years",
  `Average weekly total cash earnings` = "$", `Average weekly ordinary time cash earnings` = "$", `Average hourly total cash earnings` = "$", `Average hourly ordinary time cash earnings` = "$",
  `Average weekly total hours paid for` = "hours", `Average weekly ordinary time hours paid for` = "hours")

# Family and domestic violence is scope, whichever publication counts it; a subject that
# names a proportion gets it as the measure
fdv <- c("Family and domestic violence defendants finalised" = "Defendants finalised", "Family and domestic violence defendants with a guilty outcome" = "Defendants with a guilty outcome",
         "Offenders of family and domestic violence" = "Offenders", "Family and domestic violence related proceedings" = "Police proceedings", "Victims of family and domestic violence" = "Victims")
subject_rule <- function(e, subject, pub) {
  pop <- e[["population"]]; offence <- e[["victim_offence"]]
  if (!is.null(pop) && pop %in% names(fdv) && is.null(e[["scope"]])) { e[["scope"]] <- "Family and domestic violence-related"; e[["population"]] <- unname(fdv[pop]) }
  if (!is.null(offence) && str_detect(offence, " proportions$")) { e[["victim_offence"]] <- str_remove(offence, " proportions$"); e[["measure"]] <- "Proportion" }
  # Mixed tables: measure comes from the unit or the default, so a subject can't replace a labelled Proportion
  if (pub %in% c("pc-report-on-government-services-justice", "prisoners-australia") && identical(e[["measure"]], "Number")) e[["measure"]] <- NULL
  e
}

# Releases whose reference period reaches harmonise() through fallback_periods
fallback_releases <- sprintf("%d-%02d", 2001:2024, (2:25) %% 100)

# "Proportion" in Recorded Crime - Offenders police proceedings tables changed meaning
# twice: the Total row and column show which (qa: rows sum to 100, or a Total is 100, or
# neither). Plain Proportion is a share of the method, from 2012-13 on. First match wins.
denominators <- list(
  list(pattern = "method of proceeding.*(?:combined selected.*45190DO003_201011|45190DO002_201112)", set = list(measure = "Proportion of all proceedings")),
  list(pattern = "method of proceeding.*45190DO[0-9]+_(?:200809|200910|201011)", set = list(measure = "Proportion of proceedings for the offence")))
unit_from_measure[c("Proportion of all proceedings", "Proportion of proceedings for the offence")] <- list("%", "%")

# A column heading is no population: the title says who is counted ("UNSENTENCED PRISONERS")
replace_population <- list("Prisoners", "Offenders of family and domestic violence", "Family and domestic violence related proceedings", "Victims of family and domestic violence")

# Sheets whose recipe has no unit row
title_units <- list(list(pattern = "Table 1 ALL PERSONS, Victims of physical assault by selected characteristics.New South Wales.*2009.10", set = list(unit = "'000")))
