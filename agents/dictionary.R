#!/usr/bin/env Rscript
# Dimension dictionary maintenance. Run from the project root.
#   Rscript agents/dictionary.R check    # check dictionary/dimensions.csv
#   Rscript agents/dictionary.R report   # write dictionary/usage.csv and dictionary/proposed.csv

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(readr)
})

source("R/expand_excel_range.R")

DICTIONARY_PATH <- "dictionary/dimensions.csv"
SNAKE_CASE <- "^[a-z][a-z0-9]*(_[a-z0-9]+)*$"
TABLE_META_NAMES <- c("table_title", "table_subtitle", "notes", "source")

norm_name <- function(x) {
  x %>% str_to_lower() %>% str_remove_all("\\(([a-z]{1,2}|[0-9]{1,2})\\)") %>%
    str_replace_all("[^a-z0-9]+", "_") %>% str_remove_all("^_+|_+$")
}

read_dictionary <- function() {
  read_csv(DICTIONARY_PATH, col_types = cols(.default = col_character()), progress = FALSE) %>%
    mutate(across(everything(), ~ replace_na(.x, "")))
}

aliases_of <- function(d) {
  d %>% filter(aliases != "") %>% mutate(alias = str_split(aliases, fixed("|"))) %>% unnest(alias) %>%
    transmute(alias = norm_name(alias), name, kind, status)
}

check <- function() {
  d <- read_dictionary()
  problems <- c(
    if (!all(c("name", "kind", "status", "description", "aliases", "example_labels", "notes") %in% names(d))) "missing columns",
    d$name[!str_detect(d$name, SNAKE_CASE)] %>% { if (length(.)) paste("not snake_case:", str_flatten(., ", ")) },
    d$name[duplicated(d$name)] %>% { if (length(.)) paste("duplicate names:", str_flatten(., ", ")) },
    d$name[!d$kind %in% c("dimension", "sheet_metadata")] %>% { if (length(.)) paste("kind must be dimension or sheet_metadata:", str_flatten(., ", ")) },
    d$name[!d$status %in% c("use", "avoid")] %>% { if (length(.)) paste("status must be use or avoid:", str_flatten(., ", ")) },
    d$name[d$status == "use" & nchar(d$description) < 10] %>% { if (length(.)) paste("needs a description:", str_flatten(., ", ")) },
    d$name[d$status == "avoid" & nchar(d$notes) < 10] %>% { if (length(.)) paste("avoid rows need notes saying what to use:", str_flatten(., ", ")) }
  )
  a <- aliases_of(d)
  clash <- a %>% group_by(kind, alias) %>% filter(n_distinct(name) > 1) %>% summarise(names = str_flatten(unique(name), ", "), .groups = "drop")
  problems <- c(problems,
    if (nrow(clash)) paste0("alias '", clash$alias, "' belongs to several rows: ", clash$names),
    a %>% inner_join(d %>% select(other = name, kind), by = c("alias" = "other", "kind")) %>% filter(alias != name) %>%
      { if (nrow(.)) paste0("alias '", .$alias, "' of ", .$name, " is itself a dictionary name") })
  if (length(problems)) {
    cat(paste0("- ", problems, "\n"), sep = "")
    quit(status = 1)
  }
  cat(sprintf("%s is fine: %d dimension names, %d names to avoid, %d sheet metadata names, %d aliases\n", DICTIONARY_PATH,
              sum(d$kind == "dimension" & d$status == "use"), sum(d$status == "avoid"),
              sum(d$kind == "sheet_metadata" & d$status == "use"), nrow(a)))
}

report <- function() {
  d <- read_dictionary()
  a <- aliases_of(d)
  meta <- read_csv("source_metadata.csv", col_types = cols(.default = col_character()), trim_ws = FALSE, progress = FALSE) %>%
    select(sheet_sha256, sheets, xlsx_file, publication_id)
  paths <- list.files("tidy-recipes", pattern = "^[0-9a-f]{64}\\.json$", full.names = TRUE)

  # One row per name used in a recipe
  uses <- map_dfr(paths, function(path) {
    spec <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(spec) || !identical(spec$kind, "data")) return(NULL)
    sha <- str_remove(basename(path), "\\.json$")
    decl <- bind_rows(tibble(name = character(), description = character()),
                      map_dfr(spec$new_dimensions %||% list(), ~ tibble(name = .x$name %||% "", description = .x$description %||% "")))
    bind_rows(
      map_dfr(spec$meta_data %||% list(), ~ tibble(name = .x$name, level = "sheet meta_data", cells = .x$cells, caption = NA_character_)),
      map_dfr(spec$tables, function(t) bind_rows(
        map_dfr(t$meta_data %||% list(), ~ tibble(name = .x$name, level = "table meta_data", cells = .x$cells, caption = .x$caption %||% NA_character_)),
        map_dfr(t$headers, ~ tibble(name = .x$name, level = "header", cells = .x$cells, caption = .x$caption %||% NA_character_))))
    ) %>% mutate(sheet_sha256 = sha, status = spec$status %||% "draft",
                 declared = name %in% decl$name,
                 description = decl$description[match(name, decl$name)])
  }) %>% left_join(meta, by = "sheet_sha256")

  dims <- d %>% filter(kind == "dimension")
  sheet_names <- d %>% filter(kind == "sheet_metadata")
  classify <- function(name, level, declared) {
    key <- norm_name(name)
    pool <- if (level == "sheet meta_data") sheet_names else dims
    pool_aliases <- a %>% filter(kind == if (level == "sheet meta_data") "sheet_metadata" else "dimension")
    hit <- pool %>% filter(.data$name == .env$name)
    if (level == "table meta_data" && name %in% TABLE_META_NAMES) return(c("dictionary", name))
    if (nrow(hit)) return(c(if (hit$status[1] == "use") "dictionary" else "avoid", name))
    if (declared) return(c("declared new", NA))
    if (level == "sheet meta_data" && str_remove(name, "_[0-9]+$") %in% sheet_names$name) return(c("numbered", str_remove(name, "_[0-9]+$")))
    norm_hit <- pool %>% filter(.data$name == key)
    if (nrow(norm_hit)) return(c(if (norm_hit$status[1] == "use") "alias" else "avoid", norm_hit$name[1]))
    al <- pool_aliases %>% filter(alias == key)
    if (nrow(al)) return(c(if (al$status[1] == "use") "alias" else "avoid", al$name[1]))
    c("not in dictionary", NA)
  }
  cls <- uses %>% distinct(name, level, declared) %>%
    mutate(x = pmap(list(name, level, declared), classify), classification = map_chr(x, 1), dictionary_name = map_chr(x, 2)) %>%
    select(-x)
  uses <- uses %>% left_join(cls, by = c("name", "level", "declared"))

  usage <- uses %>% group_by(name, level, classification, dictionary_name) %>%
    summarise(recipes = n_distinct(sheet_sha256), publications = str_flatten(sort(unique(publication_id)), " | "), .groups = "drop") %>%
    arrange(level, classification != "dictionary", desc(recipes), name)
  write_csv(usage, "dictionary/usage.csv", na = "")

  # Proposals: declared names and names the dictionary does not know, with example labels
  todo <- uses %>% filter(classification %in% c("declared new", "not in dictionary"))
  label_cache <- list()
  labels_for <- function(sha, cells) {
    m <- meta %>% filter(sheet_sha256 == sha)
    if (is.null(label_cache[[sha]])) {
      label_cache[[sha]] <<- tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", m$xlsx_file), sheets = m$sheets) %>%
        transmute(address, value = coalesce(character, as.character(numeric)))
    }
    x <- label_cache[[sha]]
    x$value[x$address %in% expand_excel_range(cells) & !is.na(x$value)]
  }
  proposed <- todo %>% mutate(labels = map2(sheet_sha256, cells, labels_for)) %>%
    group_by(name, classification) %>%
    summarise(recipes = n_distinct(sheet_sha256),
              publications = str_flatten(sort(unique(publication_id)), " | "),
              descriptions = str_flatten(unique(na.omit(description)), " || "),
              captions = str_flatten(unique(na.omit(caption)), " | "),
              example_labels = str_flatten(head(unique(str_squish(unlist(labels))), 8), " | "),
              example_recipe = first(sheet_sha256), .groups = "drop") %>%
    arrange(classification, desc(recipes), name)
  write_csv(proposed, "dictionary/proposed.csv", na = "")

  cat("Recipes with data:", n_distinct(uses$sheet_sha256), "\n")
  print(usage %>% count(level, classification, wt = recipes, name = "uses") %>% pivot_wider(names_from = level, values_from = uses, values_fill = 0))
  cat(sprintf("\nWrote dictionary/usage.csv (%d names) and dictionary/proposed.csv (%d names to review)\n", nrow(usage), nrow(proposed)))
}

args <- commandArgs(TRUE)
switch(args[1] %||% "",
  check = check(),
  report = report(),
  stop("Usage: dictionary.R check | report")
)
