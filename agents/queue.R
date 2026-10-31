#!/usr/bin/env Rscript
# Work queue for recipe agents. Run from the project root.
#   Rscript agents/queue.R build                # write agents/queue.csv
#   Rscript agents/queue.R prompt <xlsx_file>   # print the worker prompt
#   Rscript agents/queue.R manifest <xlsx_file> <run_id> <log> <pi args...>
#                                               # write agents/runs/<run_id>.json, print the prompt
#   Rscript agents/queue.R shas <xlsx_file>     # print the workbook's sheet_sha256s, comma-separated
#   Rscript agents/queue.R costs                # summarise agents/logs/*.jsonl

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

RECIPE_DIR <- "tidy-recipes"
PROMPT_TEMPLATE <- "agents/prompts/worker.md"
DICTIONARY <- "dictionary/dimensions.csv"

metadata <- function() {
  # trim_ws = FALSE: some sheet names end in a space ("Table 80 ")
  read_csv("source_metadata.csv",
           col_types = cols(.default = col_character(), sheet_index = col_integer()),
           trim_ws = FALSE, progress = FALSE)
}

recipe_status <- function(shas) {
  map_chr(shas, function(sha) {
    path <- file.path(RECIPE_DIR, paste0(sha, ".json"))
    if (!file.exists(path)) return("missing")
    tryCatch(jsonlite::read_json(path)$status %||% "draft", error = function(e) "invalid")
  })
}

# Earliest period first, so later years can reuse earlier recipes as templates
period_key <- function(m) {
  coalesce(m$reference_period, m$asset_year, str_extract(m$xlsx_file, "(19|20)[0-9]{2}"))
}

build <- function() {
  # Reference-only copies (source-spreadsheets-xlsx/reference-only/) get no recipes
  m <- metadata() %>% filter(reference_only != "TRUE") %>%
    mutate(status = recipe_status(sheet_sha256), period = period_key(.))
  queue <- m %>%
    group_by(xlsx_file, publication_id, period) %>%
    summarise(sheets = n(),
              validated = sum(status == "validated"),
              needs_review = sum(status == "needs_review"),
              missing = sum(status %in% c("missing", "draft", "invalid")),
              .groups = "drop") %>%
    mutate(done = missing == 0) %>%
    arrange(publication_id, period, xlsx_file)
  write_csv(queue, "agents/queue.csv")
  message(sprintf("%d workbooks, %d done, %d sheets left", nrow(queue), sum(queue$done), sum(queue$missing)))
}

workbook_rows <- function(xlsx_file) {
  rows <- metadata() %>% filter(xlsx_file == !!xlsx_file) %>% arrange(sheet_index)
  if (nrow(rows) == 0) stop("Unknown workbook: ", xlsx_file)
  if (rows$reference_only[1] == "TRUE") {
    stop(xlsx_file, " is a reference-only copy; run its active workbook instead: ",
         unique(metadata()$xlsx_file[metadata()$source_sha256 == rows$active_sha256[1]]))
  }
  rows
}

render_prompt <- function(xlsx_file) {
  rows <- workbook_rows(xlsx_file) %>% mutate(status = recipe_status(sheet_sha256))
  r <- rows[1, ]
  period <- coalesce(r$release, r$asset_year, "unknown")

  todo <- rows %>% filter(!status %in% c("validated", "needs_review"))
  sheet_table <- todo %>%
    transmute(line = sprintf("| %s | %s | %s |",
                             map_chr(sheets, ~ jsonlite::toJSON(.x, auto_unbox = TRUE)),
                             sheet_sha256, status)) %>%
    pull(line) %>% str_flatten("\n")

  related <- c(
    if (!is.na(r$normalized_from_sha256)) paste0("- This workbook is a normalized copy of source ", r$normalized_from_sha256, ". Its layout may be trimmed but labels match."),
    if (!is.na(r$normalized_to_sha256)) paste0("- A normalized copy of this workbook exists (", r$normalized_to_sha256, "). Layout should match.")
  )

  template <- readLines(PROMPT_TEMPLATE, warn = FALSE) %>% str_flatten("\n")
  template %>%
    str_replace_all(fixed("{xlsx_file}"), xlsx_file) %>%
    str_replace_all(fixed("{publication}"), r$publication) %>%
    str_replace_all(fixed("{publisher}"), r$publisher) %>%
    str_replace_all(fixed("{period}"), period) %>%
    str_replace_all(fixed("{n_todo}"), as.character(nrow(todo))) %>%
    str_replace_all(fixed("{n_sheets}"), as.character(nrow(rows))) %>%
    str_replace_all(fixed("{sheet_table}"), sheet_table) %>%
    str_replace_all(fixed("{related}"), if (length(related)) str_flatten(related, "\n") else "- None")
}

prompt <- function(xlsx_file) cat(render_prompt(xlsx_file), "\n")

# Records the settings and exact prompt of one agent run. The recipe extension
# adds the model actually used and copies this into each recipe at submit time.
manifest <- function(xlsx_file, run_id, log, pi_args) {
  text <- render_prompt(xlsx_file)
  sha_file <- function(f) digest::digest(file = f, algo = "sha256")
  arg_value <- function(flag) pi_args[which(pi_args == flag)[1] + 1]

  skill_dir <- arg_value("--skill")
  skill_files <- sort(list.files(skill_dir, recursive = TRUE))

  run <- list(
    method = "agent",
    run_id = run_id,
    started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    workbook = xlsx_file,
    agent = list(
      fast_mode = Sys.getenv("RECIPE_FAST") == "1",
      tools = as.list(str_split_1(arg_value("--tools"), ",")),
      pi_args = as.list(pi_args)
    ),
    skill = list(
      name = basename(skill_dir),
      path = skill_dir,
      files = as.list(set_names(map_chr(file.path(skill_dir, skill_files), sha_file), skill_files))
    ),
    dictionary = list(path = DICTIONARY, sha256 = sha_file(DICTIONARY)),
    prompt = list(
      template = PROMPT_TEMPLATE,
      template_sha256 = sha_file(PROMPT_TEMPLATE),
      sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
      text = text
    ),
    log = log
  )

  dir.create("agents/runs", showWarnings = FALSE)
  jsonlite::write_json(run, file.path("agents/runs", paste0(run_id, ".json")),
                       auto_unbox = TRUE, pretty = TRUE)
  cat(text)
}

shas <- function(xlsx_file) cat(str_flatten(workbook_rows(xlsx_file)$sheet_sha256, ","), "\n")

costs <- function() {
  logs <- list.files("agents/logs", pattern = "\\.jsonl$", full.names = TRUE)
  if (!length(logs)) return(message("No logs"))
  summary <- map_dfr(logs, function(path) {
    run_file <- file.path("agents/runs", sub("\\.jsonl$", ".json", basename(path)))
    fast <- file.exists(run_file) && isTRUE(jsonlite::read_json(run_file)$agent$fast_mode)
    events <- readLines(path, warn = FALSE) %>% keep(~ str_detect(.x, '"type":"message_end"'))
    usage <- map(events, function(line) {
      e <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(e) || !identical(e$message$role, "assistant")) return(NULL)
      u <- e$message$usage
      # Pi prices the priority tier only when it is a request option, not when the
      # recipe extension sets it, so apply Pi's priority multiplier here
      if (fast && identical(e$message$provider, "openai-codex") && !is.null(u$cost$total)) {
        u$cost$total <- u$cost$total * if (identical(e$message$model, "gpt-5.5")) 2.5 else 2
      }
      u
    }) %>% compact()
    tibble(
      log = basename(path),
      fast = fast,
      turns = length(usage),
      input_tokens = sum(map_dbl(usage, ~ .x$input %||% 0)),
      cached_tokens = sum(map_dbl(usage, ~ .x$cacheRead %||% 0)),
      output_tokens = sum(map_dbl(usage, ~ .x$output %||% 0)),
      cost_usd = sum(map_dbl(usage, ~ .x$cost$total %||% 0))
    )
  })
  print(summary, n = Inf)
  message(sprintf("Total: %d runs, %.0f output tokens, $%.2f estimated at API prices (fast runs at the priority price)",
                  nrow(summary), sum(summary$output_tokens), sum(summary$cost_usd)))
}

args <- commandArgs(TRUE)
switch(args[1] %||% "",
  build = build(),
  prompt = prompt(args[2]),
  manifest = manifest(args[2], args[3], args[4], args[-(1:4)]),
  shas = shas(args[2]),
  costs = costs(),
  stop("Usage: queue.R build | prompt <xlsx_file> | manifest <xlsx_file> <run_id> <log> <pi args...> | shas <xlsx_file> | costs")
)
