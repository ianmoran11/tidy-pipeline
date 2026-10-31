
one_enhead <- function(current_header,sheet_data, table_spec){

    header_addresses <- current_header[["cells"]] %>% str_split("\\,") %>% unlist %>% map(expand_excel_range) %>% unlist()
    values_addresses <- table_spec[["values_range"]] %>% str_split("\\,") %>% unlist %>% map(expand_excel_range) %>% unlist()

    header_data <- sheet_data %>% filter(address %in% header_addresses) %>% rename(!!sym(current_header[["name"]]) := .value) %>% select(-address)
    values_data <- sheet_data %>% filter(address %in% values_addresses) 

    labelled_data <- unpivotr::enhead(data_cells = values_data,header_cells = header_data, direction = current_header[["direction"]])

    labelled_data
}
