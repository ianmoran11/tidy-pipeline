process_recipe <- function(source_metadata_df, recipe_path ){

    sha_current <- tools::file_path_sans_ext(basename(recipe_path))
    sheet_metadata_df <-  source_metadata_df %>% filter(sheet_sha256 == sha_current)

    if (nrow(sheet_metadata_df) != 1) {
        stop("No sheet in source_metadata.csv has sheet_sha256 ", sha_current, " (from ", recipe_path, ")")
    }
    if (isTRUE(as.logical(sheet_metadata_df$reference_only))) {
        stop("Recipe ", recipe_path, " is for a reference-only copy; use the active sheet ", sheet_metadata_df$active_sheet_sha256)
    }

    xlsx_path = paste0("./source-spreadsheets-xlsx/",sheet_metadata_df$xlsx_file)

    spec_ls <- jsonlite::read_json(recipe_path)
    if (!identical(spec_ls[["sheet"]], sheet_metadata_df$sheets)) {
        stop("Recipe ", recipe_path, " is for sheet '", spec_ls[["sheet"]], "' but its sha is for sheet '", sheet_metadata_df$sheets, "'")
    }

    # Read by name: tidyxl's numeric sheet index does not always follow workbook tab order
    sheet_df <- tidyxl::xlsx_cells(path = xlsx_path, sheets = sheet_metadata_df$sheets)
    # Only the box around the cells the recipe names: a state crime recipe may cover the
    # latest year's rows of a 370,000-row sheet
    refs <- unlist(rapply(spec_ls[c("meta_data", "tables")], function(x) x, how = "unlist"))
    refs <- refs[grepl("^[A-Z]{1,3}[0-9]+(:[A-Z]{1,3}[0-9]+)?(,[A-Z]{1,3}[0-9]+(:[A-Z]{1,3}[0-9]+)?)*$", refs)]
    if (length(refs)) {
        corners <- cellranger::as.cell_addr_v(unlist(stringr::str_extract_all(refs, "[A-Z]{1,3}[0-9]+")), strict = FALSE)
        rows <- range(cellranger::addr_row(corners)); cols <- range(cellranger::addr_col(corners))
        sheet_df <- sheet_df[sheet_df$row >= rows[1] & sheet_df$row <= rows[2] & sheet_df$col >= cols[1] & sheet_df$col <= cols[2], ]
    }
    # Number formats, so numbers are output as published (displayed), not as stored
    num_formats <- tidyxl::xlsx_formats(xlsx_path)$local$numFmt
    sheet_data <- sheet_df %>% mutate(.value = coalesce(character,published_value(numeric, num_formats[local_format_id]),as.character(date),as.character(logical))) %>% select(row,col,address,.value)

    # v0.2 recipes for non-data sheets (contents, notes, ...) have no tables
    table_ls <- if (spec_ls[["kind"]] %||% "data" == "data") spec_ls[["tables"]] else list()

    processed_tables <- 
        table_ls %>% map(function(table_1){

        meta_data_list <- table_1[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>% purrr::list_flatten()
        # Value cells (expanded once per table), plus published blanks inside the value grid (.value NA)
        values <- expand_excel_range(table_1[["values_range"]])
        values_data <- sheet_data %>% filter(address %in% values) %>% bind_rows(blank_value_cells(table_1, sheet_data, values))
        full_table <- map(table_1$headers, ~ one_enhead(.x, sheet_data = sheet_data, values_data = values_data)) %>%
            reduce(full_join, by = c("row", "col", "address", ".value"))

        list(
        tidy_table_list = purrr::transpose(as.list(full_table)),
        meta_data_list = meta_data_list
        ) 

        }) 

        meta_data_list <- spec_ls[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>% purrr::list_flatten()

return(
    list(
        sheet_metata =  meta_data_list, 
        tables =  processed_tables,
        # Where the sheet comes from, for later stages (e.g. harmonise())
        source = list(sheet_sha256 = sha_current,
                      publication_id = sheet_metadata_df$publication_id,
                      reference_period = sheet_metadata_df$reference_period)
    ) 
)

}