# Expands "A1", "A1:B3", or a comma-separated list of these into cell addresses
# (rows vary fastest within each part, as expand.grid gives). Vectorised parsing:
# 36 expansions per sheet made this a hotspot.
expand_excel_range <- function(x) {
  parts <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))
  m <- regmatches(parts, regexec("^\\$?([A-Za-z]+)\\$?([0-9]+)(?::\\$?([A-Za-z]+)\\$?([0-9]+))?$", parts))
  if (any(lengths(m) == 0)) stop("Not a cell range: ", paste(parts[lengths(m) == 0], collapse = ", "))
  col <- function(s) vapply(strsplit(toupper(s), ""), function(l) Reduce(function(a, b) a * 26 + b, match(l, LETTERS)), 1)
  unlist(lapply(m, function(p) {
    p[4:5][p[4:5] == ""] <- p[2:3]
    rows <- as.integer(p[3]):as.integer(p[5]); cols <- col(p[2]):col(p[4])
    paste0(rep(cellranger::num_to_letter(cols), each = length(rows)), rows)
  }))
}
