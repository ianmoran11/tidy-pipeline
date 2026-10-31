# One-off: add `generation` to recipes written before submit_recipe recorded it.
# Run from the project root: Rscript orchestrator/qa/seeds/backfill_generation.R [--dry-run]
suppressPackageStartupMessages({ library(dplyr); library(purrr); library(stringr) })

dry_run <- "--dry-run" %in% commandArgs(TRUE)
sha <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
sha_file <- function(f) digest::digest(file = f, algo = "sha256")
now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

skill_dir <- "agents/skills/tidy-recipe-authoring"
template <- "agents/prompts/worker.md"

# pi arguments in agents/run_one.sh for all logged runs (unchanged since)
pi_args <- list("--print", "--mode", "json", "--no-session", "--approve",
  "--no-extensions", "-e", "builtin:codemode", "-e", "agents/extension/recipe-tools.ts",
  "--no-skills", "--skill", skill_dir, "--no-context-files", "--no-prompt-templates",
  "--model", "openai-codex/gpt-6.1-sol", "--thinking", "medium",
  "--tools", "read,write,edit,codemode,list_workbook_sheets,sheet_grid,find_template_recipes,validate_recipe,run_recipe,submit_recipe")
tools <- as.list(str_split_1(pi_args[[length(pi_args)]], ","))

# Skill files as they were before today's edits to recipe-format.md. SKILL.md
# comes from each log; the other files were not changed after the runs.
skill_files <- sort(list.files(skill_dir, recursive = TRUE))
format_md <- readLines(file.path(skill_dir, "references/recipe-format.md"), warn = FALSE)
format_md_then <- format_md[!str_detect(format_md, "^\\| `(validation|generation)` \\|")]
known_then <- set_names(map_chr(file.path(skill_dir, skill_files), sha_file), skill_files)
known_then[["references/recipe-format.md"]] <- sha(paste0(str_flatten(format_md_then, "\n"), "\n"))

parse_log <- function(path) {
  lines <- readLines(path, warn = FALSE)
  keep_line <- str_detect(lines, fixed('"type":"session"')) |
    (str_detect(lines, fixed('"type":"message_start"')) & str_detect(lines, fixed('"role":"user"'))) |
    (str_detect(lines, fixed('"type":"message_end"')) & str_detect(lines, fixed('"role":"assistant"'))) |
    (str_detect(lines, fixed('"type":"tool_execution_start"')) & str_detect(lines, '"toolName":"(write|edit|read)"')) |
    (str_detect(lines, fixed('"type":"tool_execution_end"')) & str_detect(lines, fixed('"toolName":"read"')))
  events <- map(lines[keep_line], jsonlite::fromJSON, simplifyVector = FALSE)
  type <- map_chr(events, "type")

  session <- events[[which(type == "session")[1]]]
  user <- events[type == "message_start"][[1]]$message
  assistant <- map(events[type == "message_end"], "message")
  settings <- unique(map_chr(assistant, ~ paste(.x$provider, .x$model, .x$thinkingLevel, sep = "|")))
  if (length(settings) != 1) stop(path, ": mixed model settings ", str_flatten(settings, ", "))
  s <- str_split_1(settings, fixed("|"))

  starts <- events[type == "tool_execution_start"]
  call_path <- set_names(map_chr(starts, ~ .x$args$path %||% NA_character_), map_chr(starts, "toolCallId"))
  call_tool <- map_chr(starts, "toolName")
  written <- unique(basename(call_path[call_tool %in% c("write", "edit")]))

  # Skill files the agent read: hash exactly what it saw
  files <- known_then
  read_files <- character()
  for (e in events[type == "tool_execution_end"]) {
    rel <- str_match(call_path[[e$toolCallId]], paste0(basename(skill_dir), "/(.+)$"))[, 2]
    if (is.na(rel) || !rel %in% skill_files || isTRUE(e$isError)) next
    seen <- sha(str_flatten(map_chr(e$result$content, ~ .x$text %||% "")))
    if (rel != "SKILL.md" && seen != known_then[[rel]]) warning(path, ": ", rel, " read differs from the assumed version")
    files[[rel]] <- seen
    read_files <- c(read_files, rel)
  }
  if (!"SKILL.md" %in% read_files) stop(path, ": SKILL.md was not read")

  text <- user$content[[1]]$text
  xlsx <- str_match(text, "workbook `([^`]+)`")[, 2]
  started <- format(as.POSIXct(substr(session$timestamp, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  list(
    written = written,
    generation = list(
      method = "agent",
      run_id = paste0(format(as.POSIXct(started, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", substr(xlsx, 1, 12)),
      started_at = started,
      workbook = xlsx,
      agent = list(harness = "pi", pi_version = "1.4.0", provider = s[1], model = s[2], thinking_level = s[3],
                   session_id = session$id, tools = tools, pi_args = pi_args),
      skill = list(name = basename(skill_dir), path = skill_dir, files = as.list(files)),
      prompt = list(template = template, template_sha256 = sha_file(template), sha256 = sha(text), text = text),
      log = path,
      backfilled = list(
        at = now,
        note = paste("Recorded after the run from its log. pi_version (checked with pi --version before the run)",
                     "and pi_args (agents/run_one.sh) were not logged; all other fields come from the log.",
                     "Skill hashes are of the text the agent read, or of the file version at the time.")
      )
    )
  )
}

logs <- list.files("agents/logs", pattern = "^[0-9a-f]{64}\\.jsonl$", full.names = TRUE)
runs <- map(logs, parse_log)
owner <- map_dfr(runs, ~ tibble(file = .x$written, run = .x$generation$run_id))
dups <- owner %>% count(file) %>% filter(n > 1)
if (nrow(dups)) stop("Recipes written by more than one run: ", str_flatten(dups$file, ", "))
by_run <- set_names(map(runs, "generation"), map_chr(runs, ~ .x$generation$run_id))

write_recipe <- function(path, spec) {
  first <- c("version", "sheet_sha256", "sheet", "kind", "status", "reason", "template_from", "agent_notes",
             "meta_data", "tables", "validation", "generation")
  spec <- spec[c(intersect(first, names(spec)), setdiff(names(spec), first))]
  if (!dry_run) jsonlite::write_json(spec, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

# Recipes written outside the agent runs, from this project's interactive Pi session
session_file <- Sys.getenv("PI_SESSION_FILE")
session <- map(readLines(session_file, warn = FALSE), jsonlite::fromJSON, simplifyVector = FALSE)
request <- keep(session, ~ identical(.x$message$role, "user") &&
                  str_starts(.x$message$content[[1]]$text %||% "", "Can you create another json spec file"))[[1]]
writer <- keep(session, function(e) identical(e$message$role, "assistant") &&
                 any(map_lgl(e$message$content, ~ identical(.x$name, "write") &&
                               str_detect(.x$arguments$path %||% "", "030b9f92cd9e13d8")))) [[1]]
interactive <- list(
  "030b9f92cd9e13d80700987874240b3da9b56f34a94dd98714d5f6a87ec8ff58.json" = list(
    method = "interactive",
    created_at = paste0(substr(writer$timestamp, 1, 19), "Z"),
    agent = list(harness = "pi", provider = writer$message$provider, model = writer$message$model,
                 thinking_level = writer$message$thinkingLevel, session_id = basename(session_file) %>% str_extract("[0-9a-f-]{36}")),
    prompt = list(sha256 = sha(request$message$content[[1]]$text), text = request$message$content[[1]]$text),
    note = paste("Written by the assistant in an interactive Pi session, with the earlier conversation as context;",
                 "not by a recipe agent. Later upgraded to v0.2 (stub_heading A6 added) in the same session.")
  ),
  "58b330ab0c5c6a3285b2f12d1ae02b36bbc1c20948a84605a6ccb33e056ef6e4.json" = list(
    method = "manual",
    note = paste("Written by hand. In an interactive Pi session the assistant fixed its JSON syntax,",
                 "upgraded it to v0.2, and added stub_heading A6.")
  )
)

summary <- list()
for (path in list.files("tidy-recipes", pattern = "^[0-9a-f]{64}\\.json$", full.names = TRUE)) {
  f <- basename(path)
  spec <- jsonlite::read_json(path, simplifyVector = FALSE)
  if (!is.null(spec$generation)) { summary$already <- c(summary$already, f); next }
  run <- owner$run[owner$file == f]
  gen <- if (length(run)) by_run[[run]] else interactive[[f]]
  if (is.null(gen)) { summary$unmatched <- c(summary$unmatched, f); next }
  spec$generation <- gen
  write_recipe(path, spec)
  summary[[gen$method]] <- c(summary[[gen$method]], f)
}

cat(if (dry_run) "DRY RUN\n" else "", sep = "")
for (k in names(summary)) cat(k, length(summary[[k]]), "\n")
cat("runs:", length(runs), " skill files read per run:", str_flatten(map_chr(runs, ~ as.character(length(.x$generation$skill$files))), ","), "\n")
cat("SKILL.md versions seen:", str_flatten(unique(map_chr(runs, ~ substr(.x$generation$skill$files[["SKILL.md"]], 1, 12))), ", "), "\n")
cat("recipe-format.md versions seen:", str_flatten(unique(map_chr(runs, ~ substr(.x$generation$skill$files[["references/recipe-format.md"]], 1, 12))), ", "), "\n")
