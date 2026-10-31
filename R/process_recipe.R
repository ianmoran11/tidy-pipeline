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
    # Number formats, so numbers are output as published (displayed), not as stored
    num_formats <- tidyxl::xlsx_formats(xlsx_path)$local$numFmt
    sheet_data <- sheet_df %>% mutate(.value = coalesce(character,published_value(numeric, num_formats[local_format_id]),as.character(date),as.character(logical))) %>% select(row,col,address,.value)

    # v0.2 recipes for non-data sheets (contents, notes, ...) have no tables
    table_ls <- if (spec_ls[["kind"]] %||% "data" == "data") spec_ls[["tables"]] else list()

    processed_tables <- 
        table_ls %>% map(function(table_1){

        meta_data_list <- table_1[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>% purrr::list_flatten()
        # Published blanks inside the value grid become records with .value NA
        blanks <- blank_value_cells(table_1, sheet_data)
        full_table <- map(table_1$headers, ~ one_enhead(.x, sheet_data = sheet_data, table_spec = table_1, blank_cells = blanks)) %>% reduce(full_join)

        list(
        tidy_table_list = full_table %>% group_by(row_number()) %>% nest() %>% pull(data) %>% map(as.list),
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