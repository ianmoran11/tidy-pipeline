# Labels a table's value cells (values_data: row, col, address, .value) with one header:
# the header's cells become a dimension named after the header, attached in the
# header's unpivotr direction.
one_enhead <- function(current_header, sheet_data, values_data) {
    header_data <- sheet_data %>% filter(address %in% expand_excel_range(current_header[["cells"]])) %>%
        rename(!!sym(current_header[["name"]]) := .value) %>% select(-address)
    unpivotr::enhead(data_cells = values_data, header_cells = header_data, direction = current_header[["direction"]])
}
