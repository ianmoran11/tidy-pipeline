# Runs extraction -> normalise -> harmonise -> identify outside targets, with the current
# R/ code and specs, on every admitted sheet with a recipe in the matching publications.
# Use it before a long rebuild to list all harmonisation contradictions (which would stop
# the build) and spec gaps at once, and to make the rows a spec seed reads
# (e.g. qa/seeds/seed_victims_specs.R). Safe to run while agents write recipes: a sheet
# whose recipe can't be read is reported as an error.
# Usage: Rscript orchestrator/qa/stage_sheets.R <publication_id regex> <rows.rds | -> [cores]   (- = errors only)
# Writes <rows.rds> (one row per record, plus sheet, pub, subject and title) and prints
# errors by stage.
suppressMessages({library(dplyr); library(purrr); library(stringr); library(tidyr); library(rlang); library(unpivotr)})
args <- commandArgs(TRUE); pubs <- args[1]; out <- args[2]; cores <- as.integer(args[3] %||% 3)
for (f in c("R/published_value.R", "R/expand_excel_range.R", "R/one_enhead.R", "R/blank_value_cells.R", "R/process_recipe.R",
            "R/normalise.R", "R/harmonise.R", "R/identify.R", "R/select_sheets.R")) source(f)
m <- readr::read_csv("source_metadata.csv", col_types = readr::cols(.default = "c", reference_only = "l", sheet_index = "i"), na = c("", "NA"), trim_ws = FALSE, show_col_types = FALSE)
ns <- jsonlite::read_json("normalisation/normalisation_spec.json"); hs <- jsonlite::read_json("harmonisation/harmonisation_spec.json"); ms <- jsonlite::read_json("measures/measure_spec.json")
s <- select_sheets(m, jsonlite::read_json("sources/dataset_selection.json")) %>% filter(has_recipe, str_detect(publication_id, pubs))
run <- function(i) tryCatch({
  d <- process_recipe(s[i, ], s$recipe_path[i])
  h <- tryCatch(harmonise(normalise(d, ns), hs), error = function(e) e)
  if (inherits(h, "error")) return(list(sheet = s$sheet_sha256[i], stage = "harmonise", error = conditionMessage(h)))
  r <- identify(h, ms); x <- unlist(map(r$tables, "tidy_table_list"), recursive = FALSE)
  if (!length(x) || out == "-") return(list(sheet = s$sheet_sha256[i]))
  d <- as.data.frame(data.table::rbindlist(x, fill = TRUE)); d[] <- lapply(d, as.character)
  d$sheet <- s$sheet_sha256[i]; d$pub <- s$publication_id[i]; d$subject <- r$source$subject %||% ""
  d$title <- str_trunc(paste(unlist(r$sheet_metata$table_title), collapse = " "), 120)
  list(sheet = s$sheet_sha256[i], rows = d)
}, error = function(e) list(sheet = s$sheet_sha256[i], stage = "extract", error = conditionMessage(e)))
res <- parallel::mclapply(seq_len(nrow(s)), run, mc.cores = cores)
err <- keep(res, ~ !is.null(.x$error))
if (out != "-") saveRDS(bind_rows(map(res, "rows")), out)
cat("sheets:", nrow(s), "| errors:", length(err), "\n")
if (length(err)) {
  e <- tibble(stage = map_chr(err, "stage"), error = str_replace(map_chr(err, "error"), " at [0-9a-f]{64} [A-Z]+[0-9]+", ""))
  print(as.data.frame(count(e, stage, error = str_trunc(error, 160), sort = TRUE)), right = FALSE)
}
