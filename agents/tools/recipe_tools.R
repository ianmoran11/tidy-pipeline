#!/usr/bin/env Rscript
# CLI behind the recipe agent tools. Run from the project root:
#   Rscript agents/tools/recipe_tools.R <command> '<json params>'
# Prints one JSON object on stdout. Exits 1 with {"error": ...} on failure.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(tidyr)
  library(stringr)
  library(rlang)
  library(readr)
})

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

TOOL_VERSION <- "0.2.0"
RECIPE_DIR <- "tidy-recipes"
XLSX_DIR <- "source-spreadsheets-xlsx"
CACHE_DIR <- "agents/cache/fingerprints"
KINDS <- c("data", "contents", "notes", "empty", "unsupported")
STATUSES <- c("draft", "validated", "needs_review")
RESERVED_NAMES <- c("row", "col", "address", ".value")
DIRECTIONS <- c("N", "NNW", "NNE", "E", "ENE", "ESE", "S", "SSE", "SSW", "W", "WNW", "WSW",
                "ABOVE", "BELOW", "LEFT", "RIGHT",
                "up", "up-left", "up-right", "right", "right-up", "right-down",
                "down", "down-left", "down-right", "left", "left-up", "left-down",
                "up-ish", "right-ish", "down-ish", "left-ish")
CELLS_PATTERN <- "^[A-Z]{1,3}[0-9]+(:[A-Z]{1,3}[0-9]+)?(,[A-Z]{1,3}[0-9]+(:[A-Z]{1,3}[0-9]+)?)*$"
DICTIONARY_PATH <- "dictionary/dimensions.csv"
SNAKE_CASE <- "^[a-z][a-z0-9]*(_[a-z0-9]+)*$"
# Names a table's meta_data may use besides dimension names
TABLE_META_NAMES <- c("table_title", "table_subtitle", "notes", "source")


# Helpers ----------------------------------------------------------------------

emit <- function(x) {
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  cat("\n")
}

fail <- function(...) {
  emit(list(error = paste0(...)))
  quit(status = 1)
}

load_metadata <- function() {
  # trim_ws = FALSE: some sheet names end in a space ("Table 80 ")
  read_csv("source_metadata.csv",
           col_types = cols(.default = col_character(), sheet_index = col_integer()),
           trim_ws = FALSE, progress = FALSE)
}

sheet_row <- function(meta, sha) {
  r <- meta %>% filter(sheet_sha256 == sha)
  if (nrow(r) != 1) fail("Unknown sheet_sha256: ", sha)
  r
}

# Reference-only copies live in source-spreadsheets-xlsx/reference-only/
xlsx_path <- function(r) if (!is.null(r$xlsx_path) && !is.na(r$xlsx_path)) r$xlsx_path else file.path(XLSX_DIR, r$xlsx_file)

is_reference_only <- function(r) identical(r$reference_only, "TRUE")

# Non-blank cells of one sheet with the value text the pipeline produces.
# Sheets are read by name: tidyxl's numeric index does not follow tab order.
read_sheet <- function(r, formats = FALSE) {
  cells <- tidyxl::xlsx_cells(xlsx_path(r), sheets = r$sheets) %>%
    mutate(value = coalesce(character, as.character(numeric), as.character(date),
                            as.character(logical), error)) %>%
    filter(!is.na(value), str_trim(value) != "")
  if (formats) {
    fmt <- tidyxl::xlsx_formats(xlsx_path(r))
    cells <- cells %>%
      mutate(bold = fmt$local$font$bold[local_format_id] %in% TRUE,
             indent = coalesce(fmt$local$alignment$indent[local_format_id], 0L))
  }
  cells
}

recipe_path_for <- function(sha) file.path(RECIPE_DIR, paste0(sha, ".json"))

read_recipe_quietly <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
}

safe_expand <- function(x) {
  tryCatch(expand_excel_range(x), error = function(e) NULL)
}

first_n <- function(x, n = 15) head(unique(x), n)


# Dimension dictionary ---------------------------------------------------------

# "Age group (years)(a)" -> "age_group_years"
norm_name <- function(x) {
  x %>% str_to_lower() %>% str_remove_all("\\(([a-z]{1,2}|[0-9]{1,2})\\)") %>%
    str_replace_all("[^a-z0-9]+", "_") %>% str_remove_all("^_+|_+$")
}

norm_label <- function(x) str_squish(str_to_lower(str_remove_all(x, "\\(([a-z]{1,2}|[0-9]{1,2})\\)")))

load_dictionary <- function() {
  d <- read_csv(DICTIONARY_PATH, col_types = cols(.default = col_character()), progress = FALSE) %>%
    mutate(across(everything(), ~ replace_na(.x, "")))
  aliases <- d %>% filter(aliases != "") %>%
    mutate(alias = str_split(aliases, fixed("|"))) %>% unnest(alias) %>%
    transmute(alias = norm_name(alias), name, kind, status)
  list(entries = d, aliases = aliases)
}

# Closest dictionary names by shared words and shared example labels
suggest_names <- function(name, labels, dict, n = 3) {
  d <- dict$entries %>% filter(kind == "dimension", status == "use")
  stop_words <- c("of", "the", "and", "or", "by", "in", "to", "a", "no", "type")
  words <- function(x) setdiff(unique(unlist(str_split(norm_name(x), "_"))), c("", stop_words))
  target_words <- words(name)
  target_labels <- unique(norm_label(labels))
  score <- map_dbl(seq_len(nrow(d)), function(i) {
    length(intersect(target_words, words(c(d$name[i], str_split_1(d$aliases[i], fixed("|")))))) +
      2 * length(intersect(target_labels, norm_label(str_split_1(d$example_labels[i], fixed("|")))))
  })
  keep <- order(-score)[seq_len(min(n, sum(score > 0)))]
  d$name[keep]
}

# NULL when `name` is acceptable for a dimension, otherwise an error message
check_dimension_name <- function(name, dict, declared, labels = character()) {
  d <- dict$entries
  if (name %in% d$name[d$kind == "dimension" & d$status == "use"] || name %in% declared) return(NULL)
  key <- norm_name(name)
  entry <- d %>% filter(kind == "dimension", name == key)
  if (nrow(entry) && entry$status[1] == "avoid") return(paste0("'", name, "' is too vague. ", entry$notes[1]))
  if (nrow(entry)) return(paste0("use the dictionary name '", key, "' (snake_case); keep the publisher's wording in caption"))
  alias <- dict$aliases %>% filter(alias == key, kind == "dimension")
  if (nrow(alias) && alias$status[1] == "avoid") {
    return(paste0("'", name, "' is too vague. ", d$notes[d$name == alias$name[1]][1]))
  }
  if (nrow(alias)) return(paste0("use the dictionary name '", alias$name[1], "' instead of '", name, "'; keep the publisher's wording in caption"))
  closest <- suggest_names(name, labels, dict)
  paste0("'", name, "' is not in ", DICTIONARY_PATH, ". Use a dictionary name",
         if (length(closest)) paste0(" (closest: ", str_flatten(closest, ", "), ")"),
         " or declare a specific new name in new_dimensions")
}

check_sheet_meta_name <- function(name, dict) {
  d <- dict$entries %>% filter(kind == "sheet_metadata")
  allowed <- d$name[d$status == "use"]
  if (name %in% allowed) return(NULL)
  base <- str_remove(name, "_[0-9]+$")
  if (base != name && base %in% allowed) {
    return(paste0("use one '", base, "' item with comma-separated cells instead of numbered names like '", name, "'"))
  }
  key <- norm_name(name)
  entry <- d %>% filter(name == key)
  if (nrow(entry) && entry$status[1] == "avoid") return(entry$notes[1])
  alias <- dict$aliases %>% filter(alias == key, kind == "sheet_metadata")
  if (nrow(alias)) return(paste0("use '", alias$name[1], "' instead of '", name, "'"))
  paste0("sheet meta_data names must be one of ", str_flatten(allowed, ", "),
         ". Labels that apply to every value in a table are dimensions: put them in that table's meta_data")
}

# Text with years, numbers, and footnote markers removed, for comparing layouts
normalise_label <- function(x) {
  x %>%
    str_to_lower() %>%
    str_remove_all("\\(([a-z]{1,2}|[0-9]{1,2})\\)") %>%
    str_replace_all("[0-9]+", "#") %>%
    str_squish()
}

sheet_fingerprint <- function(r) {
  dir.create(CACHE_DIR, recursive = TRUE, showWarnings = FALSE)
  cache <- file.path(CACHE_DIR, paste0(r$sheet_sha256, ".rds"))
  if (file.exists(cache)) return(readRDS(cache))

  cells <- read_sheet(r)
  text <- cells %>% filter(!is.na(character))
  fp <- list(
    positioned = unique(paste(text$col, normalise_label(text$character))),
    labels = unique(normalise_label(text$character)),
    title = text %>% filter(row <= 6, str_detect(character, "^Table")) %>% pull(character) %>% first()
  )
  tmp <- tempfile(tmpdir = CACHE_DIR)
  saveRDS(fp, tmp)
  file.rename(tmp, cache)
  fp
}

jaccard <- function(a, b) if (length(union(a, b)) == 0) 0 else length(intersect(a, b)) / length(union(a, b))


# Commands ---------------------------------------------------------------------

cmd_list_workbook_sheets <- function(p) {
  meta <- load_metadata()
  xlsx_file <- p$xlsx_file %||% sheet_row(meta, p$sheet_sha256)$xlsx_file
  rows <- meta %>% filter(xlsx_file == !!xlsx_file)
  if (nrow(rows) == 0) fail("Unknown xlsx_file: ", xlsx_file)

  cells <- tidyxl::xlsx_cells(xlsx_path(rows[1, ])) %>%
    mutate(value = coalesce(character, as.character(numeric), as.character(date),
                            as.character(logical), error)) %>%
    filter(!is.na(value), str_trim(value) != "")

  sheets <- rows %>%
    arrange(sheet_index) %>%
    pmap(function(...) {
      r <- list(...)
      sc <- cells %>% filter(sheet == r$sheets)
      recipe <- read_recipe_quietly(recipe_path_for(r$sheet_sha256))
      list(
        sheet = r$sheets,
        sheet_sha256 = r$sheet_sha256,
        sheet_index = r$sheet_index,
        nonblank_cells = nrow(sc),
        numeric_cells = sum(!is.na(sc$numeric)),
        last_cell = if (nrow(sc)) paste0(cellranger::num_to_letter(max(sc$col)), max(sc$row)) else NA,
        heading = sc %>% filter(row <= 6, !is.na(character)) %>% arrange(row, col) %>%
          pull(character) %>% str_trunc(120) %>% head(3) %>% as.list(),
        recipe = if (is.null(recipe)) NULL else
          list(kind = recipe$kind %||% "data", status = recipe$status %||% "draft",
               version = recipe$version %||% NA)
      )
    })

  r1 <- rows[1, ]
  copies <- meta %>% filter(active_sha256 == r1$source_sha256) %>% distinct(xlsx_file, reference_copy_type)
  list(
    xlsx_file = xlsx_file,
    source_sha256 = r1$source_sha256,
    reference_only = is_reference_only(r1),
    note = if (is_reference_only(r1)) paste0("Reference-only ", r1$reference_copy_type, " of ", meta$xlsx_file[match(r1$active_sha256, meta$source_sha256)],
                                             ". Do not write recipes for it; see source-spreadsheets-xlsx/reference-only/reference-only.csv.") else NULL,
    reference_copies = map2(copies$xlsx_file, copies$reference_copy_type, ~ list(xlsx_file = .x, copy_type = .y)),
    publication_id = r1$publication_id,
    publication = r1$publication,
    publisher = r1$publisher,
    source_release_id = r1$source_release_id,
    release = r1$release,
    asset_year = r1$asset_year,
    normalization = r1$normalization,
    normalized_from_sha256 = r1$normalized_from_sha256,
    normalized_to_sha256 = r1$normalized_to_sha256,
    sheets = sheets
  )
}

cmd_sheet_grid <- function(p) {
  meta <- load_metadata()
  r <- sheet_row(meta, p$sheet_sha256)
  max_chars <- p$max_value_chars %||% 80
  max_lines <- p$max_lines %||% 250
  cells <- read_sheet(r, formats = TRUE)

  dims <- list(max_row = max(c(0, cells$row)), max_col = max(c(0, cells$col)))
  if (!is.null(p$range)) {
    lim <- tryCatch(cellranger::as.cell_limits(p$range), error = function(e) fail("Bad range: ", p$range))
    cells <- cells %>% filter(between(row, lim$ul[1], lim$lr[1]), between(col, lim$ul[2], lim$lr[2]))
  }

  shown <- cells %>%
    arrange(row, col) %>%
    mutate(flags = paste0(if_else(bold, "*", ""), if_else(indent > 0, paste0(">", indent), "")))
  # Quote text values one at a time so leading spaces stay visible
  shown$text <- ifelse(is.na(shown$numeric) & is.na(shown$date),
                       vapply(str_trunc(shown$value, max_chars),
                              function(v) jsonlite::toJSON(v, auto_unbox = TRUE), character(1)),
                       shown$value)
  # Show a long run of identical cells along a row once, e.g. a footnote that a
  # publisher's workbook repeats out to column XFD
  min_run <- 20
  shown <- shown %>%
    group_by(row) %>%
    mutate(run = cumsum(is.na(lag(col)) | col != lag(col) + 1 | text != lag(text) | flags != lag(flags))) %>%
    group_by(row, run) %>%
    summarise(item = if (n() >= min_run) paste0(first(address), ":", last(address), first(flags), "=", first(text), " (", n(), " identical cells)")
                     else str_flatten(paste0(address, flags, "=", text), " | "),
              .groups = "drop")

  lines <- shown %>%
    group_by(row) %>%
    summarise(line = paste0(first(row), ": ", str_flatten(item, " | ")), .groups = "drop")

  truncated <- nrow(lines) > max_lines
  next_row <- if (truncated) lines$row[max_lines + 1] else NULL
  lines <- head(lines, max_lines)

  list(
    sheet = r$sheets,
    sheet_sha256 = r$sheet_sha256,
    xlsx_file = r$xlsx_file,
    dims = dims,
    legend = "row: ADDRESS[flags]=value | ... ; text is JSON-quoted (leading spaces matter), numbers are bare; flags: * bold, >n indent level. Blank cells are omitted. 20 or more identical cells in a row are shown once as FIRST:LAST=value (n identical cells).",
    reference_only = is_reference_only(r),
    grid = str_flatten(lines$line, "\n"),
    truncated = truncated,
    next_row = next_row
  )
}

cmd_find_template_recipes <- function(p) {
  meta <- load_metadata()
  target <- sheet_row(meta, p$sheet_sha256)
  limit <- p$limit %||% 5

  recipe_shas <- list.files(RECIPE_DIR, pattern = "^[0-9a-f]{64}\\.json$") %>% str_remove("\\.json$")
  candidates <- meta %>%
    filter(sheet_sha256 %in% recipe_shas, sheet_sha256 != target$sheet_sha256,
           publication_id == target$publication_id)

  if (nrow(candidates) == 0) return(list(sheet_sha256 = target$sheet_sha256, templates = list()))

  tfp <- sheet_fingerprint(target)
  scored <- candidates %>%
    mutate(fp = map(seq_len(n()), ~ sheet_fingerprint(candidates[.x, ])),
           label_similarity = map_dbl(fp, ~ round(jaccard(tfp$labels, .x$labels), 3)),
           layout_similarity = map_dbl(fp, ~ round(jaccard(tfp$positioned, .x$positioned), 3)),
           title = map_chr(fp, ~ .x$title %||% NA_character_)) %>%
    arrange(desc(label_similarity), desc(layout_similarity)) %>%
    head(limit)

  list(
    sheet_sha256 = target$sheet_sha256,
    note = "label_similarity: share of the same text labels (years and numbers ignored). layout_similarity: same labels in the same columns. Row positions can still differ, so check every address against sheet_grid.",
    templates = scored %>%
      pmap(function(...) {
        x <- list(...)
        recipe <- read_recipe_quietly(recipe_path_for(x$sheet_sha256))
        list(sheet_sha256 = x$sheet_sha256, sheet = x$sheets, xlsx_file = x$xlsx_file,
             release = x$release, asset_year = x$asset_year, title = x$title,
             status = recipe$status %||% "draft", kind = recipe$kind %||% "data",
             layout_similarity = x$layout_similarity, label_similarity = x$label_similarity,
             recipe_path = recipe_path_for(x$sheet_sha256))
      })
  )
}

validate_spec <- function(path, meta) {
  errors <- character()
  warnings <- character()
  err <- function(...) errors <<- c(errors, paste0(...))
  warn <- function(...) warnings <<- c(warnings, paste0(...))

  if (!file.exists(path)) return(list(ok = FALSE, errors = paste("No such file:", path)))
  spec <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE),
                   error = function(e) e)
  if (inherits(spec, "error")) {
    return(list(ok = FALSE, errors = paste("Invalid JSON:", conditionMessage(spec))))
  }

  sha <- str_remove(basename(path), "\\.json$")
  r <- meta %>% filter(sheet_sha256 == sha)
  if (nrow(r) != 1) return(list(ok = FALSE, errors = paste("File name is not a known sheet_sha256:", basename(path))))
  if (is_reference_only(r)) {
    return(list(ok = FALSE, errors = paste0("Sheet ", sha, " is in a reference-only ", r$reference_copy_type, " (", r$xlsx_file,
      "). Write the recipe for the same sheet of the active workbook instead: tidy-recipes/", r$active_sheet_sha256, ".json")))
  }

  if (!identical(spec$version, "0.2")) err("version must be \"0.2\"")
  if (!identical(spec$sheet_sha256, sha)) err("sheet_sha256 must equal the file name sha (", sha, ")")
  if (!identical(spec$sheet, r$sheets)) err("sheet must be exactly ", jsonlite::toJSON(r$sheets, auto_unbox = TRUE), " (got ", jsonlite::toJSON(spec$sheet, auto_unbox = TRUE), ")")
  kind <- spec$kind %||% ""
  if (!kind %in% KINDS) err("kind must be one of ", str_flatten(KINDS, ", "))
  if (!(spec$status %||% "") %in% STATUSES) err("status must be one of ", str_flatten(STATUSES, ", "))

  cells <- read_sheet(r)
  max_row <- max(c(0, cells$row))
  max_col <- max(c(0, cells$col))

  check_cells <- function(x, where) {
    if (!is.character(x) || length(x) != 1 || !str_detect(x, CELLS_PATTERN)) {
      err(where, ": cells must look like \"A1\", \"A1:B3\" or \"A8:A11,A13\" with no spaces (got ", jsonlite::toJSON(x, auto_unbox = TRUE), ")")
      return(character())
    }
    addrs <- safe_expand(x)
    if (is.null(addrs)) { err(where, ": could not parse ", x); return(character()) }
    lim <- cellranger::as.cell_addr(addrs, strict = FALSE)
    outside <- addrs[cellranger::addr_row(lim) > max_row | cellranger::addr_col(lim) > max_col]
    if (length(outside)) warn(where, ": ", length(outside), " cells beyond the last non-blank cell (", cellranger::num_to_letter(max_col), max_row, ")")
    addrs
  }

  dict <- load_dictionary()
  cell_text <- function(addrs) cells$value[cells$address %in% addrs]
  sheet_text <- unique(str_squish(cells$value[!is.na(cells$character)]))

  # Names not in the dictionary, declared by the agent for review
  declared <- character()
  for (nd in spec$new_dimensions %||% list()) {
    nm <- nd$name %||% ""
    known <- nm %in% dict$entries$name || norm_name(nm) %in% c(dict$entries$name, dict$aliases$alias)
    if (!str_detect(nm, SNAKE_CASE)) err("new_dimensions: '", nm, "' must be snake_case, e.g. '", norm_name(nm), "'")
    else if (known) err("new_dimensions: '", nm, "' is already in ", DICTIONARY_PATH, "; use the dictionary name instead of declaring it")
    else if (nchar(str_trim(nd$description %||% "")) < 15) err("new_dimensions: '", nm, "' needs a description of what its labels are")
    else declared <- c(declared, nm)
  }
  used_names <- character()

  check_caption <- function(item, where) {
    if (is.null(item$caption)) return()
    if (!is.character(item$caption) || length(item$caption) != 1 || str_trim(item$caption) == "") {
      err(where, ": caption must be the publisher's caption text")
    } else if (!str_squish(item$caption) %in% sheet_text) {
      warn(where, ": caption ", jsonlite::toJSON(item$caption, auto_unbox = TRUE), " does not match any cell's text")
    }
  }

  check_meta <- function(items, where, level) {
    if (is.null(items)) return(character())
    if (!is.list(items) || !is.null(names(items))) { err(where, ": meta_data must be an array"); return(character()) }
    nms <- map_chr(items, ~ .x$name %||% "")
    if (any(nms == "")) err(where, ": every meta_data item needs a name")
    if (anyDuplicated(nms[nms != ""])) err(where, ": duplicate meta_data names")
    unlist(map(seq_along(items), function(i) {
      mwhere <- paste0(where, " meta_data '", nms[i], "'")
      addrs <- check_cells(items[[i]]$cells, mwhere)
      problem <- if (nms[i] == "") NULL
        else if (level == "sheet") check_sheet_meta_name(nms[i], dict)
        else if (nms[i] %in% TABLE_META_NAMES) NULL
        else check_dimension_name(nms[i], dict, declared, cell_text(addrs))
      if (!is.null(problem)) err(mwhere, ": ", problem)
      if (level == "table") { used_names <<- c(used_names, nms[i]); check_caption(items[[i]], mwhere) }
      addrs
    }))
  }

  check_meta(spec$meta_data, "sheet", "sheet")

  if (kind == "data") {
    tables <- spec$tables
    if (!is.list(tables) || length(tables) == 0 || !is.null(names(tables))) {
      err("kind data needs a non-empty tables array")
    } else {
      tnames <- map_chr(tables, ~ .x$name %||% "")
      if (any(tnames == "")) err("every table needs a name")
      if (anyDuplicated(tnames)) err("table names must be unique")
      for (i in seq_along(tables)) {
        t <- tables[[i]]
        where <- paste0("table '", tnames[i], "'")
        range <- check_cells(t$range, paste0(where, " range"))
        values <- check_cells(t$values_range, paste0(where, " values_range"))
        if (length(range) && length(values) && length(setdiff(values, range))) {
          err(where, ": values_range has ", length(setdiff(values, range)), " cells outside range, e.g. ", str_flatten(first_n(setdiff(values, range), 5), ", "))
        }
        check_meta(t$meta_data, where, "table")
        if (!is.list(t$headers) || length(t$headers) == 0) {
          err(where, ": needs at least one header")
          next
        }
        hnames <- map_chr(t$headers, ~ .x$name %||% "")
        if (any(hnames == "")) err(where, ": every header needs a name")
        if (anyDuplicated(hnames)) err(where, ": duplicate header names")
        if (any(hnames %in% RESERVED_NAMES)) err(where, ": header names cannot be ", str_flatten(RESERVED_NAMES, ", "))
        tmeta <- map_chr(t$meta_data %||% list(), ~ .x$name %||% "")
        if (any(hnames %in% tmeta)) err(where, ": a header and a table meta_data item share a name")
        for (h in t$headers) {
          hwhere <- paste0(where, " header '", h$name %||% "", "'")
          if (!(h$direction %||% "") %in% DIRECTIONS) err(hwhere, ": direction must be one of ", str_flatten(DIRECTIONS, ", "))
          haddr <- check_cells(h$cells, hwhere)
          overlap <- intersect(haddr, values)
          if (length(overlap)) err(hwhere, ": header cells overlap values_range at ", str_flatten(first_n(overlap, 5), ", "))
          if (nzchar(h$name %||% "")) {
            problem <- check_dimension_name(h$name, dict, declared, cell_text(haddr))
            if (!is.null(problem)) err(hwhere, ": ", problem)
            used_names <- c(used_names, h$name)
          }
          check_caption(h, hwhere)
        }
      }
    }
    # meta_data labels must be label cells, never another table's values
    if (is.list(tables) && length(tables)) {
      all_values <- unique(unlist(map(tables, ~ if (is.character(.x$values_range)) safe_expand(.x$values_range))))
      meta_items <- c(spec$meta_data %||% list(), unlist(map(tables, ~ .x$meta_data %||% list()), recursive = FALSE))
      for (md in meta_items) {
        overlap <- intersect(if (is.character(md$cells)) safe_expand(md$cells) else character(), all_values)
        if (length(overlap)) err("meta_data '", md$name %||% "", "' uses value cells ", str_flatten(first_n(overlap, 5), ", "), "; use the label cell for that block")
      }
    }
    unused <- setdiff(declared, used_names)
    if (length(unused)) warn("new_dimensions declared but not used: ", str_flatten(unused, ", "))
  } else if (kind %in% KINDS) {
    if (!is.character(spec$reason) || str_trim(spec$reason %||% "") == "") err("kind ", kind, " needs a reason")
    if (length(spec$tables %||% list())) err("kind ", kind, " must not have tables")
  }

  list(ok = length(errors) == 0, errors = errors, warnings = warnings, spec = spec, meta_row = r, cells = cells)
}

cmd_validate_recipe <- function(p) {
  meta <- load_metadata()
  v <- validate_spec(p$path, meta)
  list(path = p$path, ok = v$ok, errors = as.list(v$errors %||% character()), warnings = as.list(v$warnings %||% character()))
}

# Runs the recipe through the pipeline code and measures coverage
run_checks <- function(path, meta) {
  v <- validate_spec(path, meta)
  out <- list(path = path, valid = v$ok, errors = as.list(v$errors %||% character()),
              warnings = as.list(v$warnings %||% character()))
  if (!v$ok) return(c(out, list(passed = FALSE, failures = list("recipe is not valid; see errors"))))

  spec <- v$spec
  cells <- v$cells
  nonblank <- cells$address
  numeric_cells <- cells$address[!is.na(cells$numeric)]
  failures <- character()

  sheet_meta_addrs <- unlist(map(spec$meta_data %||% list(), ~ expand_excel_range(.x$cells)))

  if (spec$kind != "data") {
    if (length(numeric_cells)) {
      failures <- c(failures, paste0("kind ", spec$kind, " but the sheet has ", length(numeric_cells),
                                     " numeric cells, e.g. ", str_flatten(first_n(numeric_cells, 5), ", ")))
    }
    return(c(out, list(kind = spec$kind, numeric_cells = length(numeric_cells),
                       passed = length(failures) == 0, failures = as.list(failures))))
  }

  messages <- character()
  result <- withCallingHandlers(
    tryCatch(process_recipe(mutate(meta, sheet_index = as.integer(sheet_index)), path), error = function(e) e),
    message = function(m) invokeRestart("muffleMessage"),
    warning = function(w) { messages <<- c(messages, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  if (inherits(result, "error")) {
    return(c(out, list(passed = FALSE, failures = list(paste("process_recipe failed:", conditionMessage(result))),
                       r_warnings = as.list(first_n(messages, 5)))))
  }

  all_referenced <- unique(c(
    sheet_meta_addrs,
    unlist(map(spec$tables, function(t) c(
      expand_excel_range(t$values_range),
      unlist(map(t$headers, ~ expand_excel_range(.x$cells))),
      unlist(map(t$meta_data %||% list(), ~ expand_excel_range(.x$cells)))
    )))
  ))
  value_lists <- map(spec$tables, ~ expand_excel_range(.x$values_range))
  value_counts <- table(unlist(value_lists))
  double_covered <- names(value_counts)[value_counts > 1]
  if (length(double_covered)) failures <- c(failures, paste0(length(double_covered), " cells are in more than one table's values_range, e.g. ", str_flatten(first_n(double_covered, 5), ", ")))

  table_reports <- map(seq_along(spec$tables), function(i) {
    t <- spec$tables[[i]]
    res <- result$tables[[i]]
    records <- res$tidy_table_list
    header_names <- map_chr(t$headers, "name")
    values <- value_lists[[i]]
    range <- expand_excel_range(t$range)

    blank_values <- setdiff(values, nonblank)
    unaccounted <- setdiff(intersect(range, nonblank), all_referenced)
    missing <- keep(records, function(rec) any(map_lgl(header_names, ~ is.null(rec[[.x]]) || is.na(rec[[.x]]))))
    missing_meta <- names(keep(res$meta_data_list, ~ length(.x) == 0 || all(is.na(.x))))

    tf <- character()
    if (length(records) == 0) tf <- c(tf, "no records")
    if (length(blank_values)) tf <- c(tf, paste0(length(blank_values), " blank cells in values_range, e.g. ", str_flatten(first_n(blank_values, 5), ", ")))
    if (length(unaccounted)) tf <- c(tf, paste0(length(unaccounted), " non-blank cells in range are not in values, headers or meta_data, e.g. ", str_flatten(first_n(unaccounted, 8), ", ")))
    if (length(missing)) tf <- c(tf, paste0(length(missing), " records lack a header label, e.g. ", str_flatten(first_n(map_chr(missing, "address"), 5), ", ")))
    if (length(missing_meta)) tf <- c(tf, paste0("table meta_data with no value: ", str_flatten(missing_meta, ", ")))
    failures <<- c(failures, if (length(tf)) paste0("table '", t$name, "': ", tf))

    idx <- unique(c(1, ceiling(length(records) / 2), length(records)))
    list(
      name = t$name,
      records = length(records),
      meta_data = map(res$meta_data_list, ~ str_trunc(as.character(.x), 100)),
      blank_values = length(blank_values),
      unaccounted_in_range = length(unaccounted),
      records_missing_labels = length(missing),
      samples = if (length(records)) map(records[idx[idx > 0]], ~ map(.x, ~ if (is.character(.x)) str_trunc(.x, 80) else .x)) else list()
    )
  })

  table_areas <- unique(unlist(map(spec$tables, ~ expand_excel_range(.x$range))))
  numeric_outside <- setdiff(numeric_cells, table_areas)
  if (length(numeric_outside)) failures <- c(failures, paste0(length(numeric_outside), " numeric cells are outside every table range, e.g. ", str_flatten(first_n(numeric_outside, 8), ", ")))
  text_outside <- setdiff(nonblank, c(table_areas, all_referenced))

  c(out, list(
    kind = "data",
    sheet_meta_data = map(result$sheet_metata, ~ str_trunc(as.character(.x), 100)),
    tables = table_reports,
    records = sum(map_int(table_reports, "records")),
    double_covered = length(double_covered),
    numeric_outside_tables = length(numeric_outside),
    unreferenced_text_outside_tables = as.list(first_n(text_outside, 10)),
    r_warnings = as.list(first_n(messages, 5)),
    passed = length(failures) == 0,
    failures = as.list(failures)
  ))
}

cmd_run_recipe <- function(p) {
  run_checks(p$path, load_metadata())
}

cmd_submit_recipe <- function(p) {
  meta <- load_metadata()
  checks <- run_checks(p$path, meta)
  if (!isTRUE(checks$valid)) {
    return(list(path = p$path, status = "not submitted", errors = as.list(checks$errors),
                note = "Fix the errors with validate_recipe, then submit again."))
  }

  spec <- jsonlite::read_json(p$path, simplifyVector = FALSE)
  status <- if (isTRUE(checks$passed)) "validated" else "needs_review"
  if (!is.null(p$agent_notes) && nzchar(p$agent_notes)) spec$agent_notes <- p$agent_notes
  # Agent settings and prompt, added by the extension in agent runs. Manual
  # submits leave any existing record alone. The pipeline does not read it.
  if (!is.null(p$generation)) spec$generation <- p$generation
  spec$status <- status
  spec$validation <- list(
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    tool_version = TOOL_VERSION,
    records = checks$records %||% 0L,
    failures = checks$failures %||% list()
  )
  # Keep a stable key order
  first <- c("version", "sheet_sha256", "sheet", "kind", "status", "reason", "template_from", "agent_notes", "new_dimensions", "meta_data", "tables", "validation", "generation")
  spec <- spec[c(intersect(first, names(spec)), setdiff(names(spec), first))]

  tmp <- tempfile(tmpdir = dirname(p$path), fileext = ".tmp")
  jsonlite::write_json(spec, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  file.rename(tmp, p$path)

  list(path = p$path, status = status, records = checks$records %||% 0L,
       failures = checks$failures %||% list(), warnings = as.list(checks$warnings))
}


# Dispatch ---------------------------------------------------------------------

args <- commandArgs(TRUE)
if (length(args) < 1) fail("Usage: recipe_tools.R <command> '<json params>'")
params <- if (length(args) >= 2) jsonlite::fromJSON(args[2], simplifyVector = FALSE) else list()

handler <- switch(args[1],
  list_workbook_sheets = cmd_list_workbook_sheets,
  sheet_grid = cmd_sheet_grid,
  find_template_recipes = cmd_find_template_recipes,
  validate_recipe = cmd_validate_recipe,
  run_recipe = cmd_run_recipe,
  submit_recipe = cmd_submit_recipe,
  fail("Unknown command: ", args[1])
)

result <- tryCatch(handler(params), error = function(e) fail(conditionMessage(e)))
emit(result)
