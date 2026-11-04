# Published (displayed) values: the stored number rounded the way Excel shows it
# under the cell's number format, e.g. 2.37887238760836 with format "0.0" -> "2.4".
# A percentage format shows the stored fraction times 100: -0.204 with "0.0%" -> "-20.4"
# (the % sign itself is the unit, as in tables that print percentages as plain numbers).

# tidyxl 1.0.10 misreports Excel's built-in formats 3, 4 and 37-40 with ";" in
# place of the thousands separator ("#;##0.00" for "#,##0.00"), which reads as
# two format sections. Restore the real format strings.
TIDYXL_BUILTIN_FIXES <- c(
  "#;##0" = "#,##0",
  "#;##0.00" = "#,##0.00",
  "#;##0 ;(#;##0)" = "#,##0 ;(#,##0)",
  "#;##0 ;[Red](#;##0)" = "#,##0 ;[Red](#,##0)",
  "#;##0.00;(#;##0.00)" = "#,##0.00;(#,##0.00)",
  "#;##0.00;[Red](#;##0.00)" = "#,##0.00;[Red](#,##0.00)"
)

fix_numfmt <- function(numfmt) {
  fixed <- unname(TIDYXL_BUILTIN_FIXES[numfmt])
  ifelse(is.na(fixed), numfmt, fixed)
}

# The format section that applies to a value of this sign, without quoted text, escaped
# characters, [colour/locale] blocks and _/* padding
format_section <- function(numfmt, x) {
  numfmt <- fix_numfmt(numfmt)
  mapply(function(fmt, v) {
    if (is.na(fmt)) return(NA_character_)
    sections <- strsplit(gsub('"[^"]*"|\\\\.|\\[[^]]*\\]|[_*].', "", fmt), ";", fixed = TRUE)[[1]]
    if (!length(sections)) return("")
    if (!is.na(v) && v < 0 && length(sections) >= 2) sections[2]
    else if (!is.na(v) && v == 0 && length(sections) >= 3) sections[3]
    else sections[1]
  }, numfmt, x, USE.NAMES = FALSE)
}

# Decimal places shown by an Excel number format for a value of this sign.
# NA for formats left as stored: General, text, scientific, fractions.
format_decimals <- function(numfmt, x) {
  vapply(format_section(numfmt, x), function(s) {
    if (is.na(s) || s %in% c("General", "@") || grepl("[eE][+-]|/", s)) return(NA_integer_)
    dec <- regmatches(s, regexpr("(?<=\\.)[0#?]+", s, perl = TRUE))
    if (length(dec)) nchar(dec) else 0L
  }, 1L, USE.NAMES = FALSE)
}

# TRUE where the format shows the value as a percentage
format_percent <- function(numfmt, x) grepl("%", format_section(numfmt, x), fixed = TRUE)

# Round like Excel's display: take the 15-significant-digit decimal form and round
# half away from zero. R's round() differs: round(2.5) is 2, round(2.675, 2) is 2.67.
excel_round <- function(x, digits) {
  mapply(function(v, d) {
    if (is.na(v) || is.na(d) || !is.finite(v)) return(v)
    s <- sprintf("%.14e", abs(v))
    mantissa <- gsub(".", "", sub("e.*$", "", s), fixed = TRUE)
    exponent <- as.integer(sub("^.*e", "", s))
    keep <- exponent + 1L + d
    if (keep < 0L) return(0)
    if (keep >= 15L) return(v)
    kept <- if (keep > 0L) as.numeric(substr(mantissa, 1L, keep)) else 0
    if (substr(mantissa, keep + 1L, keep + 1L) >= "5") kept <- kept + 1
    sign(v) * kept / 10^(keep - exponent - 1L)
  }, x, digits, USE.NAMES = FALSE)
}

# Number as text without scientific notation (as.character(100000) is "1e+05")
number_text <- function(x) {
  out <- trimws(formatC(x, digits = 15, format = "fg"))
  out[is.na(x)] <- NA_character_
  out
}

# Asterisks that a number format adds as quoted literal text ("*"#,##0.0 shows 7.3 as
# *7.3: ABS and RoGS mark estimates with a high relative standard error this way), from
# the format section that applies (positive;negative;zero). NA where there are none.
format_stars <- function(numfmt, x) {
  sections <- strsplit(ifelse(is.na(numfmt), "", numfmt), ";", fixed = TRUE)
  k <- ifelse(is.na(x) | x > 0, 1L, ifelse(x < 0, 2L, 3L))
  section <- mapply(function(s, i) if (length(s) >= i) s[i] else if (length(s)) s[1] else "", sections, k)
  literals <- vapply(regmatches(section, gregexpr('"[^"]*"', section)), paste, "", collapse = "")
  stringr::str_extract(literals, "\\*+")
}

published_value <- function(x, numfmt) {
  if (!length(x)) return(character())  # a sheet with no cells (an xlsm's VBA module)
  pct <- format_percent(numfmt, x); x[pct] <- x[pct] * 100
  d <- format_decimals(numfmt, x)
  text <- number_text(ifelse(is.na(d), x, excel_round(x, d)))
  stars <- format_stars(numfmt, x)
  ifelse(is.na(stars) | is.na(text), text, paste0(stars, text))
}
