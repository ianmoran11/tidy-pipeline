# Writes the integrated tables as UTF-8 CSV files (missing values as empty fields)
# and returns their paths, for a format = "file" target. A list of tables (series, one
# per publication) is written as a folder of files named after them.
write_integrated <- function(tables, dir = "integrated") {
  dir.create(dir, showWarnings = FALSE)
  write <- function(table, path) { data.table::fwrite(table, path, na = ""); path }
  unlist(purrr::imap(tables, function(table, name) {
    if (is.data.frame(table)) return(write(table, file.path(dir, paste0(name, ".csv"))))
    sub <- file.path(dir, name); unlink(c(sub, paste0(sub, ".csv")), recursive = TRUE); dir.create(sub)  # no stale files
    purrr::imap_chr(table, function(t, part) write(t, file.path(sub, paste0(part, ".csv"))))
  }), use.names = FALSE)
}
