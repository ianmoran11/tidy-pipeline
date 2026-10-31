# Does the new check flag any other recipe? (validate every data recipe)
suppressMessages({library(purrr); library(stringr)})
files <- list.files("tidy-recipes", pattern = "^[0-9a-f]{64}\\.json$", full.names = TRUE)
res <- map_chr(files, function(p) {
  out <- system2("Rscript", c("agents/tools/recipe_tools.R", "validate_recipe", shQuote(jsonlite::toJSON(list(path = p), auto_unbox = TRUE))), stdout = TRUE)
  e <- jsonlite::fromJSON(paste(out, collapse = ""))$errors
  hit <- e[str_detect(e, "uses value cells")]
  if (length(hit)) paste(basename(p), hit[1]) else NA_character_
})
cat(sum(!is.na(res)), "recipes flagged\n"); cat(head(na.omit(res), 5), sep = "\n")
