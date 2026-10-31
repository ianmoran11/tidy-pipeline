# Writes the integrated tables as UTF-8 CSV files (missing values as empty fields)
# and returns their paths, for a format = "file" target.
write_integrated <- function(tables, dir = "integrated") {
  dir.create(dir, showWarnings = FALSE)
  purrr::imap_chr(tables, function(table, name) {
    path <- file.path(dir, paste0(name, ".csv"))
    data.table::fwrite(table, path, na = "")
    path
  })
}
