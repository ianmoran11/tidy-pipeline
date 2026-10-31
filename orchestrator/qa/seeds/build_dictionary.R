# One-off: write the first version of dictionary/dimensions.csv.
# Example labels come from the recipes reviewed so far where available.
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tibble)})

norm_name <- function(x) x %>% str_to_lower() %>% str_remove_all("\\(([a-z]{1,2}|[0-9]{1,2})\\)") %>%
  str_replace_all("[^a-z0-9]+", "_") %>% str_remove_all("^_+|_+$")

d <- tribble(
  ~name, ~kind, ~status, ~description, ~aliases, ~curated_examples, ~notes,
  # time
  "period", "dimension", "use", "Reference period the value relates to: a year, financial year, quarter, month, date, or a period of change between two periods.",
    "year|years|reference period|financial year|year ending|date|quarter|month|time period", "2019–20|2017|Dec 2023|30 June 2021|2008–09 to 2009–10",
    "Not the release date. Lengths of time are not periods: use case_duration, time_in_care, time_in_placement, time_on_order or supervision_duration.",
  # geography
  "state", "dimension", "use", "State or territory, including national (Australia) totals.",
    "state/territory|state or territory|states and territories|jurisdiction", "NSW|Vic|Qld|WA|SA|Tas.|ACT|NT|Aust.|Australia", "Keep labels as published, e.g. Tas(b)(c), Aust., Australia excl NT.",
  "remoteness_area", "dimension", "use", "ABS Remoteness Area (ASGS) of the person or place.",
    "remoteness area|remoteness areas|remoteness", "Major cities|Inner regional|Outer regional|Remote|Very remote", "",
  "socioeconomic_area", "dimension", "use", "Socioeconomic position of the area, usually an ABS SEIFA (IRSD) quintile or decile.",
    "socioeconomic areas|socioeconomic status|socio-economic status|seifa quintile", "1 (lowest)|2|3|4|5 (highest)", "",
  # person characteristics
  "sex", "dimension", "use", "Sex of the person. Court defendant tables may include Organisations.",
    "gender", "Males|Females|Persons|Boys|Girls|Organisations", "",
  "age_group", "dimension", "use", "Age or age group, including single years of age and open-ended groups.",
    "age|age (years)|age group (years)|age groups|age in years", "10–14|15–19|<1|Unborn|18 years and over|65 years and over",
    "Mean or median age published along the same axis stays as a label; mention it in agent_notes.",
  "indigenous_status", "dimension", "use", "Aboriginal and Torres Strait Islander (Indigenous) status, however it is worded.",
    "indigenous status|aboriginal and torres strait islander status|first nations status", "First Nations|Aboriginal and Torres Strait Islander|Indigenous|Non-Indigenous|Not stated",
    "Block labels such as 'Indigenous children' or 'Non-Indigenous children' are values of this dimension.",
  "disability_status", "dimension", "use", "Disability status of the person.",
    "disability", "With disability|Without disability|Not stated", "",
  # what the value is
  "measure", "dimension", "use", "What the value measures: a count, rate, proportion, ratio, average, median or other named quantity.",
    "data item|measures", "Number|Rate|Per cent|Proportion (%)|Offender rate(b)|AVERAGE WEEKLY TOTAL CASH EARNINGS ($)",
    "Use for headings such as NUMBER / PROPORTION (%) that split values into blocks. Use unit for a separate units column or row, and estimate_type for estimate vs standard error.",
  "unit", "dimension", "use", "Unit of measurement published separately from the measure, such as a units column in Report on Government Services tables.",
    "units|unit of measure", "no.|%|$|$'000|$m|rate|hr/day", "",
  "estimate_type", "dimension", "use", "Whether the value is an estimate or a measure of its sampling error.",
    "estimate type|estimate or standard error", "ESTIMATE|STANDARD ERROR|RSE (%)", "",
  # crime and justice
  "principal_offence", "dimension", "use", "Principal offence of the offender, defendant or finalisation, classified by ANZSOC at any level (division, subdivision or group).",
    "principal offence|principal federal offence (anzsoc)|selected principal federal offence (anzsoc)|principal offence (anzsoc)", "01 Homicide and related offences|011 Murder|Acts intended to cause injury",
    "Divisions and their subdivisions are often listed together. Keep them in this dimension and describe the hierarchy in agent_notes, or put a separate division heading in principal_offence_division.",
  "principal_offence_division", "dimension", "use", "ANZSOC division heading shown separately above its subdivisions or groups.",
    "offence division|anzsoc division", "03 Sexual assault and related offences|10 Illicit drug offences", "",
  "most_serious_offence", "dimension", "use", "Most serious offence or charge of a prisoner (ANZSOC). A different counting rule from principal offence.",
    "most serious offence|most serious offence/charge|most serious charge", "Homicide and related offences|Theft and related offences", "",
  "court_level", "dimension", "use", "Level of court.",
    "court level|level of court", "Higher Courts|Magistrates' Courts|Children's Courts", "",
  "method_of_finalisation", "dimension", "use", "How a defendant's case was finalised.",
    "method of finalisation|finalisation method", "Acquitted|Proven guilty|Transfers to other courts|Withdrawn by prosecution|Total finalised", "",
  "method_of_finalisation_group", "dimension", "use", "Grouping of methods of finalisation shown as a heading above them.",
    "outcome group|finalisation group|adjudication status", "Adjudicated outcomes|Non-adjudicated outcomes", "",
  "principal_sentence", "dimension", "use", "Principal (most serious) sentence given to proven guilty defendants.",
    "principal sentence|sentence outcomes|sentence type", "Custodial orders|Non-custodial orders|Fines|Community service orders", "",
  "principal_sentence_group", "dimension", "use", "Grouping of principal sentences shown as a heading above them.",
    "sentence group", "Custodial orders|Non-custodial orders", "",
  "method_of_proceeding", "dimension", "use", "Police method of proceeding against an offender.",
    "method of proceeding", "Court action|Non-court action|Total proceedings", "",
  "times_proceeded_against", "dimension", "use", "Number of times an offender was proceeded against by police in the period.",
    "times proceeded against|times proceeded against by police|number of times proceeded against", "1|2|5 or more|1 time|5 times or more", "",
  "sentence_length", "dimension", "use", "Length band of a prisoner's sentence (aggregate sentence or expected time to serve).",
    "sentence length|sentence length or statistic|aggregate sentence length", "Under 3 months|2 & under 5 years|Life|Periodic detention", "",
  "sentence_basis", "dimension", "use", "Which sentence length is measured.",
    "sentence basis", "AGGREGATE SENTENCE LENGTH|EXPECTED TIME TO SERVE", "",
  "case_duration", "dimension", "use", "Time from initiation to finalisation of a court case.",
    "case duration|duration from initiation to finalisation", "Under 13 weeks|13 weeks & under 26 weeks|52 weeks & over", "",
  # child protection
  "child_protection_component", "dimension", "use", "Stage or component of the child protection system.",
    "child protection component|child protection stage", "Notifications|Investigations|Substantiations|Children on care and protection orders|Children in out-of-home care", "",
  "service_combination", "dimension", "use", "Combination of child protection services a child received.",
    "service component|service combination", "Investigation only|Care and protection order only|Investigation, order and out-of-home care", "",
  "abuse_type", "dimension", "use", "Primary type of abuse or neglect substantiated.",
    "primary type of abuse or neglect|type of abuse or neglect|abuse type", "Physical abuse|Sexual abuse|Emotional abuse|Neglect", "",
  "co_occurring_abuse_type", "dimension", "use", "Other types of abuse or neglect substantiated alongside the primary type.",
    "co-occurring type of abuse or neglect", "Physical abuse|Neglect", "",
  "investigation_outcome", "dimension", "use", "Outcome of a child protection investigation.",
    "investigation outcome|investigations outcome|outcome of investigation", "Substantiated|Not substantiated|No outcome possible", "",
  "action_type", "dimension", "use", "Action taken on a child protection notification or investigation.",
    "type of action", "Investigations finalised|Notifications resolved without investigation", "",
  "source_of_notification", "dimension", "use", "Who notified child protection services.",
    "source of notification|notifier", "Police|School personnel|Parent/guardian", "",
  "order_type", "dimension", "use", "Type of legal order: care and protection orders in child protection, supervised orders in youth justice.",
    "type of order|order type", "Long-term finalised guardianship or custody orders|Remand [unsentenced detention orders]", "",
  "order_status", "dimension", "use", "Whether a child is on a care and protection order or another order.",
    "order status", "On care and protection order|On another type of order|Not on an order", "",
  "placement_type", "dimension", "use", "Type of out-of-home care placement.",
    "type of placement|placement type", "Foster care|Relative/kinship care|Residential care|Family group homes|Independent living", "",
  "living_arrangement", "dimension", "use", "Where or with whom a child lives, including with parents.",
    "living arrangements|living arrangement|living situation", "Parents|Relatives/kin (family care)|Foster care|Children living with parents", "",
  "permanency_status", "dimension", "use", "Legal permanency arrangement of a child in out-of-home care.",
    "permanency status", "Long-term guardianship in foster care|Short-term guardianship total|Not on an order", "",
  "carer_relationship", "dimension", "use", "Relationship of the relative/kinship carer or caregiver to the child.",
    "relationship of relative/kinship carer|carer relationship|relationship to carer", "Grandparent|Aunt/uncle|Sibling|Living with Indigenous relatives or kin", "",
  "client_type", "dimension", "use", "Whether the child is a new or repeat client of child protection services.",
    "client type", "New client|Repeat client", "",
  "reunification_status", "dimension", "use", "Whether a child in care was reunified with family in the period.",
    "reunification status", "Reunified in 2020–21|Not reunified in 2020–21", "",
  "time_in_care", "dimension", "use", "Length of time a child has been in care.",
    "time in care|time in out-of-home care|length of time in care", "<12 months|1 to <2 years|3 years or more", "",
  "time_in_placement", "dimension", "use", "Length of time in the current or a continuous placement.",
    "time in continuous placement|time in placement", "<1 month|1 month to <6 months|5 years or more", "",
  "time_on_order", "dimension", "use", "Length of time a child was on a care and protection order.",
    "time on order|time on an order|length of time on an order", "<1 month|1–<3 months|8+ years", "",
  "number_of_children", "dimension", "use", "Number of children, as a count band (for example per household).",
    "number of children", "1|2|3–4|5+", "",
  "number_of_substantiations", "dimension", "use", "Number of substantiations for a child, as a count band.",
    "number of substantiations", "1|2|3|4 or more", "",
  # youth justice
  "supervision_type", "dimension", "use", "Type of youth justice supervision: community-based or detention, and their subtypes.",
    "supervision type|first supervision type|type of supervision", "Community-based supervision|Detention|Probation and similar|Remand", "",
  "supervision_history", "dimension", "use", "Whether a young person had been supervised before, or which kinds of supervision their history contains.",
    "supervision history", "First year of supervision|Previously supervised", "",
  "supervision_duration", "dimension", "use", "Length of a youth justice supervision period.",
    "duration of supervision|length of supervision|time under supervision", "0–29 days (<1 month)|365+ days (12+ months)", "",
  "completed_supervision_periods", "dimension", "use", "Number of completed supervision periods, as a count band.",
    "no. completed supervision periods|no. of completed supervision periods|number of completed supervision periods", "1|2|3|5+", "",
  "number_of_orders", "dimension", "use", "Number of orders, as a count band.",
    "number of orders", "1|2|6+", "",
  # employee earnings and hours
  "occupation", "dimension", "use", "Occupation (ANZSCO).", "occupation (anzsco)", "Managers|Professionals|Labourers", "",
  "industry", "dimension", "use", "Industry (ANZSIC).", "industry (anzsic)", "Mining|Manufacturing|Retail trade", "",
  "sector", "dimension", "use", "Public or private sector.", "sector of employment", "Public|Private|All sectors", "",
  "employer_size", "dimension", "use", "Employer size, by number of employees.", "employer size|size of employer", "Less than 20 employees|1000 or more employees", "",
  "method_of_setting_pay", "dimension", "use", "How the employee's pay is set.", "method of setting pay", "Award only|Collective agreement|Individual arrangement", "",
  "rate_of_pay", "dimension", "use", "Adult, junior, apprentice/trainee or disability rate of pay.", "rate of pay", "Adult rate of pay|Junior rate of pay", "",
  "employee_type", "dimension", "use", "Type of employee, such as permanent or fixed term versus casual.", "type of employee|employment type", "Permanent or fixed term employees|Casual employees", "",
  # report on government services
  "service", "dimension", "use", "Government service area.", "service area|services", "Police services|Courts - criminal|Corrective services|Prisons|Community corrections", "",
  "indicator", "dimension", "use", "Report on Government Services indicator or descriptor heading that a block of values belongs to.",
    "performance indicator|descriptor", "Real net operating expenditure, per day|Assaults in custody|Prisoners in education and training", "",
  # general
  "population", "dimension", "use", "Population or subgroup a block of values covers, when it is not a value of another dictionary dimension.",
    "population group|subpopulation", "All children|Children in out-of-home care|Young people under supervision during the year",
    "If the label is a value of another dimension, use that dimension: 'Indigenous children' -> indigenous_status, 'Males' -> sex.",

  # names to avoid
  "category", "dimension", "avoid", "Too generic.", "", "", "Name the dimension the labels belong to (sex, method_of_finalisation, ...). If one column stacks several characteristics under captions, make one table per section.",
  "characteristic", "dimension", "avoid", "Stacked sections.", "summary characteristics|characteristics", "", "Split stacked sections (Sex, Age, Principal offence, ...) into one table per section and name the row header after the section: sex, age_group, principal_offence. Keep the section caption as the header's caption.",
  "section", "dimension", "avoid", "Too generic.", "", "", "Name the concept. For Report on Government Services row outlines, map each level to indicator, service, measure, unit or a characteristic such as indigenous_status; declare a new name if none fits.",
  "group", "dimension", "avoid", "Too generic.", "subgroup|groups", "", "Name the concept the labels belong to. For a parent heading over child rows use the dictionary's *_group name if there is one (method_of_finalisation_group, principal_sentence_group).",
  "component", "dimension", "avoid", "Ambiguous.", "subcomponent|components", "", "Use child_protection_component, service_combination or service, or declare a specific new name.",
  "level", "dimension", "avoid", "Too generic.", "item|type|variable|class|classification|breakdown|dimension|label|value|other", "", "Name the concept the labels belong to.",
  "outcome", "dimension", "avoid", "Ambiguous.", "outcomes", "", "Use method_of_finalisation, method_of_finalisation_group or investigation_outcome, or declare a specific new name.",
  "duration", "dimension", "avoid", "Ambiguous.", "time|length of time", "", "Use case_duration, time_in_care, time_in_placement, time_on_order or supervision_duration, or declare a specific new name. Reference periods are period.",
  "statistic", "dimension", "avoid", "Ambiguous.", "statistics", "", "Use estimate_type for estimate vs standard error, otherwise measure.",
  "frequency", "dimension", "avoid", "Ambiguous.", "", "", "Use times_proceeded_against or another specific count name.",
  "supervision", "dimension", "avoid", "Ambiguous.", "", "", "Use supervision_type or supervision_history.",
  "relationship", "dimension", "avoid", "Ambiguous.", "", "", "Use carer_relationship or declare a specific relationship name.",
  "offence", "dimension", "avoid", "Ambiguous.", "offence type|offences", "", "Use principal_offence (offenders, defendants) or most_serious_offence (prisoners).",

  # sheet-level meta_data
  "table_title", "sheet_metadata", "use", "The table's title line, usually starting 'Table ...'.", "title", "", "Also allowed in a table's meta_data when a sheet holds several titled tables.",
  "table_number", "sheet_metadata", "use", "Table number when it is printed separately from the title.", "table identifier|table id", "", "",
  "table_subtitle", "sheet_metadata", "use", "Other heading lines that describe the whole table: publication name and year, population or units line.", "subtitle|publication|publication banner", "", "Also allowed in a table's meta_data.",
  "sheet_description", "sheet_metadata", "use", "Accessibility text describing the sheet, often in A1 of ABS sheets.", "accessibility text", "", "",
  "stub_heading", "sheet_metadata", "use", "Captions above the row-label column(s).", "stub|stub headings", "", "One item; list several cells with commas.",
  "notes", "sheet_metadata", "use", "Footnotes, explanatory notes, symbol legends and caveats.", "footnotes|note|explanatory notes|symbols", "", "Also allowed in a table's meta_data for notes that belong to one table.",
  "source", "sheet_metadata", "use", "Data source lines.", "sources|source fragment|data source", "", "Also allowed in a table's meta_data.",
  "release", "sheet_metadata", "use", "Release information: catalogue number, release date and time.", "release information|release date", "", "",
  "annotations", "sheet_metadata", "use", "Stray worksheet cells that belong to no table, such as unlabelled symbols or leftover values.", "worksheet annotations|unpopulated characteristics", "", "",
  "errata", "sheet_metadata", "use", "Errata and change notices.", "erratum", "", "",
  "notes_and_worksheet_annotations", "sheet_metadata", "avoid", "Mixed.", "", "", "Split into notes and annotations."
)

# Example labels from the recipes reviewed so far, where a used name maps to this entry
used <- readRDS("orchestrator/qa/cache/names.rds") %>% mutate(key = norm_name(dim), label = str_squish(label)) %>%
  filter(!is.na(label), !str_detect(label, "^(Total|All|Persons)\\b"))
d <- d %>% rowwise() %>% mutate(example_labels = {
  if (kind != "dimension" || status != "use") "" else {
    keys <- c(name, norm_name(str_split_1(aliases, "\\|")))
    seen <- used %>% filter(key %in% keys) %>% count(label, sort = TRUE) %>% pull(label) %>% str_trunc(45) %>% unique() %>% head(6)
    paste(if (length(seen) >= 3) seen else unique(c(seen, str_split_1(curated_examples, "\\|"))), collapse = "|")
  }
}) %>% ungroup() %>% select(name, kind, status, description, aliases, example_labels, notes)

dir.create("dictionary", showWarnings = FALSE)
readr::write_csv(d, "dictionary/dimensions.csv", na = "")
cat(nrow(d), "rows:", sum(d$kind == "dimension" & d$status == "use"), "dimension names,", sum(d$status == "avoid"), "names to avoid,",
    sum(d$kind == "sheet_metadata" & d$status == "use"), "sheet metadata names\n")
