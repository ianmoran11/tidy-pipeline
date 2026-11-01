# Empty cells inside a table's value grid: where a row and a column that both hold
# values in this table cross, and the cell is neither a header nor filled. They are
# published blanks, so they become records with .value NA (type_values() gives them
# the blank status). Rows or columns that are blank throughout are not recovered:
# recipes usually leave them out of the table, labels included.
blank_value_cells <- function(table_spec, sheet_data, values = expand_excel_range(table_spec[["values_range"]])) {
  headers <- unlist(lapply(table_spec[["headers"]], function(h) expand_excel_range(h[["cells"]])))
  coords <- cellranger::as.cell_addr_v(values, strict = FALSE)
  grid <- expand.grid(row = unique(cellranger::addr_row(coords)), col = unique(cellranger::addr_col(coords)))
  grid$address <- openxlsx::getCellRefs(grid[c("row", "col")])
  filled <- sheet_data$address[!is.na(sheet_data$.value)]
  tibble::as_tibble(grid[!grid$address %in% c(values, headers, filled), ]) %>% mutate(.value = NA_character_)
}
