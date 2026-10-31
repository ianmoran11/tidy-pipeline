
# Expands "A1", "A1:B3", or a comma-separated list of these into cell addresses
expand_excel_range <- function(x) {
  parts <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))

  unlist(lapply(parts, function(part) {
    bounds <- cellranger::as.cell_limits(part)

    coords <- expand.grid(
      row = bounds$ul[1]:bounds$lr[1],
      col = bounds$ul[2]:bounds$lr[2]
    )

    openxlsx::getCellRefs(coords)
  }))
}
