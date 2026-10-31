sheet_cells <- function(r) {
  tidyxl::xlsx_cells(file.path("source-spreadsheets-xlsx", r$xlsx_file), sheets = r$sheets) %>%
    mutate(.value = coalesce(character, as.character(numeric), as.character(date), as.character(logical), error)) %>%
    select(row, col, address, .value, is_blank, numeric, character)
}

# One row per (value cell, attached label): label cell address and text
recipe_labels <- function(spec, cells) {
  map_dfr(seq_along(spec$tables), function(i) {
    t <- spec$tables[[i]]
    vals <- cells %>% filter(address %in% expand_excel_range(t$values_range)) %>% select(row, col, address, .value)
    tmeta <- map_dfr(t$meta_data %||% list(), function(md) {
      cells %>% filter(address %in% expand_excel_range(md$cells), !is.na(.value)) %>%
        transmute(dim = md$name, label_cell = address, label = .value)
    })
    from_meta <- tidyr::crossing(vals %>% select(address), tmeta)
    from_headers <- map_dfr(t$headers, function(h) {
      hc <- cells %>% filter(address %in% expand_excel_range(h$cells)) %>% transmute(row, col, label_cell = address, label = .value)
      out <- tryCatch(unpivotr::enhead(vals, hc, h$direction), error = function(e) NULL)
      if (is.null(out)) return(tibble())
      out %>% transmute(address, dim = h$name, label_cell, label)
    })
    bind_rows(from_meta, from_headers) %>% mutate(table = i, table_name = t$name)
  })
}

