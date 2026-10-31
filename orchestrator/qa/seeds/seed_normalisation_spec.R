# One-off: write the first version of normalisation/normalisation_spec.json from the
# raw labels in the data target. Edit the JSON directly afterwards.
suppressMessages({library(dplyr); library(purrr); library(stringr)})

# Dimension names: dictionary aliases used by recipes written before the dictionary
usage <- readr::read_csv("dictionary/usage.csv", show_col_types = FALSE) %>%
  filter(level != "sheet meta_data", classification == "alias", name != dictionary_name) %>% distinct(name, dictionary_name)
name_map <- setNames(as.list(usage$dictionary_name), usage$name)

counts <- readRDS("orchestrator/qa/cache/raw_value_counts.rds") %>%
  mutate(dimension = coalesce(usage$dictionary_name[match(dimension, usage$name)], dimension)) %>%
  filter(!is.na(value)) %>% distinct(dimension, value)

# Footnote markers such as (a), (b)(c), "(e), (g)"; line breaks; repeated spaces
clean <- function(x) {
  x %>% str_replace_all("[\r\n]+", " ") %>% str_remove_all("\\s*\\([a-z]{1,2}\\)") %>%
    str_remove("[\\s,]+$") %>% str_squish()
}
key <- function(x) x %>% str_to_upper() %>% str_replace_all("[–—−]", "-") %>% str_remove("\\.$") %>% str_squish()

synonyms <- list(
  state = c("NSW" = "NSW|NEW SOUTH WALES|NEWS SOUTH WALES", "Vic." = "VIC|VICTORIA", "Qld" = "QLD|QUEENSLAND",
            "SA" = "SA|SOUTH AUSTRALIA", "WA" = "WA|WESTERN AUSTRALIA", "Tas." = "TAS|TASMANIA",
            "NT" = "NT|NORTHERN TERRITORY", "ACT" = "ACT|AUSTRALIAN CAPITAL TERRITORY", "Australia" = "AUST|AUS|AUSTRALIA"),
  sex = c("Males" = "MALE|MALES", "Females" = "FEMALE|FEMALES", "Persons" = "PERSONS",
          "Organisations" = "ORGANISATION|ORGANISATIONS", "Not stated" = "NOT STATED"),
  indigenous_status = c("Aboriginal and Torres Strait Islander" = paste(
                          "ABORIGINAL AND TORRES STRAIT ISLANDER|ABORIGINAL & TORRES STRAIT ISLANDER",
                          "ABORIGINAL OR TORRES STRAIT ISLANDER|INDIGENOUS|INDIGENEOUS|FIRST NATIONS", sep = "|"),
                        "Non-Indigenous" = "NON-INDIGENOUS", "Not stated" = "NOT STATED", "Total" = "TOTAL")
)

canonical <- function(dimension, value) {
  v <- clean(value)
  if (dimension == "period") v <- str_replace_all(v, "\\b(\\d{4})-(\\d{2})\\b", "\\1–\\2")
  syn <- synonyms[[dimension]]
  if (!is.null(syn)) {
    hit <- names(syn)[map_lgl(syn, ~ key(v) %in% str_split_1(.x, fixed("|")))]
    if (length(hit)) v <- hit[1]
  }
  v
}

mapped <- counts %>% mutate(to = map2_chr(dimension, value, canonical)) %>% filter(to != value, to != "")
values <- mapped %>% arrange(dimension, value) %>% split(.$dimension) %>% map(~ setNames(as.list(.x$to), .x$value))
values <- values[order(-lengths(values))]

spec <- list(
  description = paste(
    "Canonical replacements applied by normalise() in R/normalise.R, after the tidy data target.",
    "dimension_names maps a raw dimension name to its canonical name; values maps, for each canonical",
    "dimension name, a raw label to its canonical label. Names are renamed before labels are mapped.",
    "Anything not listed is left as it is. First version generated from the data: footnote markers and",
    "extra spaces removed from all labels, en dashes in year ranges, and synonyms for state, sex and",
    "indigenous_status."),
  dimension_names = name_map,
  values = values
)
dir.create("normalisation", showWarnings = FALSE)
jsonlite::write_json(spec, "normalisation/normalisation_spec.json", auto_unbox = TRUE, pretty = TRUE)
cat(length(name_map), "dimension names;", sum(lengths(values)), "label replacements across", length(values), "dimensions\n")
print(head(sort(lengths(values), decreasing = TRUE), 12))
for (d in c("state", "sex", "indigenous_status")) cat(d, "canonical labels after mapping:",
  n_distinct(counts %>% filter(dimension == d) %>% mutate(to = coalesce(unlist(values[[d]])[value], value)) %>% pull(to)), "of", sum(counts$dimension == d), "\n")
