# One-off: write the first version of measures/measure_spec.json from the title
# subjects in data_harmonised. Edit the JSON directly afterwards.
suppressMessages({library(dplyr); library(purrr); library(stringr)})
h <- targets::tar_read(data_harmonised)

subject_pattern <- paste0("^(?:FDV\\s+|ANZSOC 2023\\s+)?(?:Table\\s*[A-Z]{0,3}\\s*[0-9]+[a-z]?\\s*[:.–-]?\\s*)?",
                          "(?:Experimental data(?:\\s*\\([a-z0-9]{1,2}\\))?\\s*[–-]\\s*)?([^,]+)")
subjects <- map_dfr(h, function(s) {
  title <- str_squish(gsub("\u00a0", " ", paste(unlist(s$sheet_metata[["table_title"]]), collapse = " ")))
  subject <- str_match(title, regex(subject_pattern, ignore_case = TRUE))[, 2]
  tibble(pub = s$source$publication_id, key = str_squish(gsub("\\s*\\([a-z0-9]{1,2}\\)", "", tolower(coalesce(subject, "")))),
         n = sum(map_int(s$tables, ~ length(.x$tidy_table_list))))
}) %>% filter(key != "", n > 0) %>% count(pub, key, wt = n, name = "records")

proper <- function(x) x %>% str_replace_all("\\bcovid-19\\b", "COVID-19") %>% str_replace("^(.)", toupper) %>%
  str_replace_all("\\baboriginal\\b", "Aboriginal") %>% str_replace_all("\\btorres strait islander\\b", "Torres Strait Islander") %>%
  str_replace_all("\\bnon-indigenous\\b", "non-Indigenous") %>% str_replace_all("\\bindigenous\\b", "Indigenous") %>%
  str_replace("^Non-Indigenous|^non-Indigenous", "Non-Indigenous") %>%
  str_replace_all("\\bchildren's courts?\\b", "Children's Courts")

# Rules: scope from "(excluding ...)", court level suffixes dropped (harmonise() takes
# court_level from the title), ABS's older "proven guilty" = "with a guilty outcome",
# FDV spelt out, combined finalised/guilty tables counted as defendants finalised
# (their method_of_finalisation or population field separates the outcomes).
rule <- function(key, pub) {
  scope <- str_match(key, "\\(?(excluding [^)]+)\\)?")[, 2]
  p <- key %>% str_remove("\\s*\\(?excluding [^)]+\\)?") %>%
    str_remove("\\s*[–-]\\s*(combined )?(all|higher|magistrates'?|children'?s?) courts?$") %>%
    str_replace_all("\\bfdv[- ]related\\b", "family and domestic violence related") %>% str_replace_all("\\bfdv\\b", "family and domestic violence") %>%
    str_replace("finalised and (with a )?(proven )?guilty( outcome)?$", "finalised") %>% str_replace("proven guilty", "with a guilty outcome") %>%
    str_squish()
  base <- key %>% str_remove("\\s*\\(?excluding [^)]+\\)?") %>% str_remove("\\s*[–-]\\s*(combined )?(all|higher|magistrates'?|children'?s?) courts?$") %>% str_squish()
  out <- overrides[[pub]][[base]] %||% list(population = proper(p))
  if (!is.na(scope)) out$scope <- proper(scope)
  out
}

# Subjects that name a measure, a breakdown or a table number rather than who is counted.
overrides <- list(
  "criminal-courts-australia" = list(
    "summary characteristics of all defendants" = list(population = "Defendants finalised"),
    "summary characteristics of defendants" = list(population = "Defendants finalised"),
    "summary outcomes of defendants" = list(population = "Defendants finalised"),
    "summary outcomes for all defendants" = list(population = "Defendants finalised"),
    "duration from initiation to finalisation" = list(population = "Defendants finalised"),
    "court level and principal offence by principal sentence" = list(population = "Defendants with a guilty outcome"),
    "length of custody in a correctional institution" = list(population = "Defendants sentenced to custody in a correctional institution"),
    "length of custody" = list(population = "Defendants sentenced to custody in a correctional institution"),
    "defendants given custody in a correctional institution" = list(population = "Defendants sentenced to custody in a correctional institution"),
    "defendants sentenced to a custody in a correctional institution" = list(population = "Defendants sentenced to custody in a correctional institution"),
    "defendants given fines" = list(population = "Defendants given a fine"),
    "value of fine" = list(population = "Defendants given a fine"),
    "defendants given community service orders" = list(population = "Defendants sentenced to a community service order"),
    "defendants sentenced to community service order" = list(population = "Defendants sentenced to a community service order"),
    "length of community service order" = list(population = "Defendants sentenced to a community service order"),
    "custodial sentence by all courts" = list(population = "Defendants sentenced to a custodial order", court_level = "All Courts"),
    "custodial sentence by higher courts" = list(population = "Defendants sentenced to a custodial order", court_level = "Higher Courts"),
    "custodial sentence by magistrates' court" = list(population = "Defendants sentenced to a custodial order", court_level = "Magistrates' Courts"),
    "custodial sentence by children's court" = list(population = "Defendants sentenced to a custodial order", court_level = "Children's Courts"),
    "rate of defendants finalised" = list(population = "Defendants finalised", measure = "Rate"),
    "family and domestic violence offences" = list(population = "Family and domestic violence offences")),
  "federal-defendants-australia" = list(
    "federal defendants" = list(population = "Federal defendants finalised"),
    "federal offences" = list(population = "Federal offences"),
    "federal defendants finalised with a guilty outcome" = list(population = "Federal defendants with a guilty outcome")),
  "prisoners-australia" = list(
    "crude imprisonment rate" = list(population = "Prisoners", measure = "Crude imprisonment rate"),
    "crude imprisonment rates" = list(population = "Prisoners", measure = "Crude imprisonment rate"),
    "age standardised imprisonment rate" = list(population = "Prisoners", measure = "Age standardised imprisonment rate"),
    "age standardised imprisonment rates" = list(population = "Prisoners", measure = "Age standardised imprisonment rate"),
    "imprisonment rate" = list(population = "Prisoners", measure = "Imprisonment rate"),
    "imprisonment rates" = list(population = "Prisoners", measure = "Imprisonment rate"),
    "proportion of prisoners" = list(population = "Prisoners", measure = "Proportion"),
    "number of prisoners" = list(population = "Prisoners", measure = "Number"),
    "number of sentenced prisoners" = list(population = "Sentenced prisoners", measure = "Number"),
    "number of unsentenced prisoners" = list(population = "Unsentenced prisoners", measure = "Number"),
    "sentencing characteristics" = list(population = "Sentenced prisoners"),
    "selected prisoner characteristics" = list(population = "Prisoners"),
    "prisoner characteristics" = list(population = "Prisoners"),
    "all sentenced prisoners" = list(population = "Sentenced prisoners"),
    "indigenous sentenced prisoners" = list(population = "Sentenced prisoners", indigenous_status = "Aboriginal and Torres Strait Islander"),
    "aboriginal and torres strait islander sentenced prisoners" = list(population = "Sentenced prisoners", indigenous_status = "Aboriginal and Torres Strait Islander"),
    "non-indigenous sentenced prisoners" = list(population = "Sentenced prisoners", indigenous_status = "Non-Indigenous"),
    "non-indigenous prisoners" = list(population = "Prisoners", indigenous_status = "Non-Indigenous"),
    "prisoners aged 50 years and over" = list(population = "Prisoners", age_group = "50 years and over"),
    "mean and median age of prisoners" = list(population = "Prisoners"),
    "mean and median age of periodic detainees" = list(population = "Periodic detainees"),
    "mean and median aggregate sentence length of sentenced prisoners" = list(population = "Sentenced prisoners"),
    "mean and median expected time to serve of sentenced prisoners" = list(population = "Sentenced prisoners"),
    "time on remand as at 30 june 2006 for unsentenced prisoners" = list(population = "Unsentenced prisoners"),
    "indicative impact of classification changes" = list(population = "Prisoners", scope = "Indicative impact of classification changes"),
    "estimated resident population" = list(population = "Persons", measure = "Estimated resident population"),
    "estimated adult resident population" = list(population = "Adults", measure = "Estimated resident population"),
    "estimated indigenous population" = list(population = "Aboriginal and Torres Strait Islander people", measure = "Estimated resident population"),
    "federal offences" = list(population = "Federal prisoners and parolees"),
    "table 33 sentenced prisoners" = list(population = "Sentenced prisoners"),
    "table 34 prisoners" = list(population = "Prisoners"),
    "table 36 prisoners" = list(population = "Prisoners"),
    "table 44 periodic detainees" = list(population = "Periodic detainees")),
  "recorded-crime-offenders" = list(
    "offender rate" = list(population = "Offenders", measure = "Offender rate"),
    "youth offender rate" = list(population = "Youth offenders", measure = "Offender rate"),
    "family and domestic violence offender rate" = list(population = "Offenders of family and domestic violence", measure = "Offender rate"),
    "police proceedings – court actions" = list(population = "Police proceedings", scope = "Court actions"),
    "family and domestic violence related proceedings by court action" = list(population = "Family and domestic violence related proceedings", scope = "Court actions"),
    "proceedings of family and domestic violence" = list(population = "Family and domestic violence related proceedings")),
  "aihw-youth-justice-australia" = list(
    "population of young people aged 10–17" = list(population = "Young people aged 10–17", measure = "Population")),
  "pc-report-on-government-services-justice" = list(
    "community corrections offender population (average daily number) and rates per 100 000 relevant adults" = list(population = "Community corrections offenders"),
    "community corrections offender population (average daily number)" = list(population = "Community corrections offenders", measure = "Average daily number"),
    "prisoner population (average daily number) and rates per 100 000 relevant adults" = list(population = "Prisoners"),
    "prisoner population (average daily number)" = list(population = "Prisoners", measure = "Average daily number"),
    "imprisonment and community corrections population rate per 100 000 adults" = list(population = "Prisoners and community corrections offenders"),
    "deaths from apparent unnatural causes by indigenous status" = list(population = "Prisoners", measure = "Deaths from apparent unnatural causes"),
    "deaths from apparent unnatural causes" = list(population = "Prisoners", measure = "Deaths from apparent unnatural causes"),
    "escapes per 100 prisoners" = list(population = "Prisoners", measure = "Escapes per 100 prisoners"),
    "assaults in custody" = list(population = "Prisoners", measure = "Assaults in custody"),
    "real net operating expenditure" = list(population = "Corrective services", measure = "Real net operating expenditure"),
    "real net operating expenditure per prisoner and per offender per day" = list(population = "Prisoners and community corrections offenders", measure = "Real net operating expenditure per day"),
    "recurrent expenditure" = list(population = "Corrective services", measure = "Recurrent expenditure"),
    "recurrent expenditure per prisoner and per offender per day" = list(population = "Prisoners and community corrections offenders", measure = "Recurrent expenditure per day"),
    "number of times offenders proceeded against by police" = list(population = "Offenders", measure = "Number"),
    "completion of community corrections orders" = list(population = "Community corrections orders", measure = "Proportion completed"),
    "prisoner education and training (per cent of eligible prisoners)" = list(population = "Eligible prisoners", measure = "Proportion in education and training", unit = "%"),
    "prisoner employment (per cent of eligible prisoners)" = list(population = "Eligible prisoners", measure = "Proportion employed", unit = "%"),
    "prisoner employment by indigenous status (per cent of eligible prisoners)" = list(population = "Eligible prisoners", measure = "Proportion employed", unit = "%"),
    "community corrections offender-to-staff ratio" = list(population = "Community corrections offenders", measure = "Offender-to-staff ratio"),
    "time out-of-cells (average hours per day)" = list(population = "Prisoners", measure = "Time out of cells", unit = "hours per day"),
    "prison design capacity utilisation" = list(population = "Prisons", measure = "Design capacity utilisation"),
    "correctional custodial facilities" = list(population = "Correctional custodial facilities"),
    "adults released from prison who returned to prison or to corrective services with a new correctional sanction within two years" = list(population = "Adults released from prison", measure = "Proportion returning within two years"),
    "adults discharged from community corrections orders who returned to corrective services with a new correctional sanction within two years" = list(population = "Adults discharged from community corrections orders", measure = "Proportion returning within two years"),
    "real recurrent expenditure (less revenue from own sources) per person on justice services" = list(population = "Justice services", measure = "Real recurrent expenditure per person"),
    "real recurrent expenditure (less revenue from own sources) on justice services by australian" = list(population = "Justice services", measure = "Real recurrent expenditure"))
)

spec_subjects <- map(split(subjects, subjects$pub), function(d) {
  pub <- d$pub[1]
  setNames(map(d$key, function(k) overrides[[pub]][[k]] %||% rule(k, pub)), d$key)
})
missing_overrides <- unlist(map(names(overrides), function(p) setdiff(names(overrides[[p]]), subjects$key[subjects$pub == p])))
if (length(missing_overrides)) cat("overrides with no matching subject:", missing_overrides, sep = "\n  ")

spec <- list(
  description = "Stage 4 (identify): what each record counts. See measures/README.md.",
  subject_pattern = subject_pattern,
  title_flags = list(
    list(pattern = "^ANZSOC 2023\\b|Preliminary ANZSOC 2023", set = list(offence_classification = "ANZSOC 2023 (preliminary)")),
    list(pattern = "Experimental data", set = list(data_status = "Experimental"))),
  measure_from_unit = list("no." = "Number", "%" = "Proportion"),
  default_measure = list("criminal-courts-australia" = "Number", "federal-defendants-australia" = "Number",
                         "prisoners-australia" = "Number", "recorded-crime-offenders" = "Number"),
  subjects = spec_subjects)
dir.create("measures", showWarnings = FALSE)
jsonlite::write_json(spec, "measures/measure_spec.json", auto_unbox = TRUE, pretty = TRUE)
cat("subjects:", nrow(subjects), "| populations:", n_distinct(unlist(map(unlist(spec_subjects, recursive = FALSE), "population"))), "\n")
