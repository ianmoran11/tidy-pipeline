library(tidyxl)
library(unpivotr)
library(cellranger)
library("openxlsx")
library(rlang)

source_metadata_df <- read_csv("source_metadata.csv")
sheet_metadata_df <-  source_metadata_df %>% filter(sheet_sha256 == "58b330ab0c5c6a3285b2f12d1ae02b36bbc1c20948a84605a6ccb33e056ef6e4")
xlsx_path = paste0("./source-spreadsheets-xlsx/",sheet_metadata_df$xlsx_file)

spec_ls <- jsonlite::read_json(paste0("./tidy-recipes/" , sheet_metadata_df$sheet_sha256, ".json"))
sheet_df <- tidyxl::xlsx_cells(path = xlsx_path, sheets = sheet_metadata_df$sheet_index)

table_1 <- spec_ls[["tables"]][[1]]

sheet_data <- sheet_df %>% mutate(.value = coalesce(character,as.character(numeric),as.character(date),as.character(logical))) %>% select(row,col,address,.value)
meta_data_list <- table_1[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>%flatten()
full_table <- map(table_1$headers, ~ one_enhead(.x, sheet_data = sheet_data, table_spec = table_1)) %>% reduce(full_join)

list(
tidy_table_list = full_table %>% group_by(row_number()) %>% nest() %>% pull(data) %>% map(as.list),
meta_data_list = meta_data_list
)  %>% str(max.level = 1)

#------------------------------

library(tidyverse)

list.files("./R", full.names = T)  %>% map(source)

source_metadata_df <- read_csv("source_metadata.csv")
sheet_metadata_df <-  source_metadata_df %>% filter(sheet_sha256 == "58b330ab0c5c6a3285b2f12d1ae02b36bbc1c20948a84605a6ccb33e056ef6e4")
xlsx_path = paste0("./source-spreadsheets-xlsx/",sheet_metadata_df$xlsx_file)

spec_ls <- jsonlite::read_json(paste0("./tidy-recipes/" , sheet_metadata_df$sheet_sha256, " copy.json"))
sheet_df <- tidyxl::xlsx_cells(path = xlsx_path, sheets = sheet_metadata_df$sheet_index)

table_ls <- spec_ls[["tables"]]

processed_tables <- 
    table_ls %>% map(function(table_1){

    sheet_data <- sheet_df %>% mutate(.value = coalesce(character,as.character(numeric),as.character(date),as.character(logical))) %>% select(row,col,address,.value)
    meta_data_list <- table_1[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>%flatten()
    full_table <- map(table_1$headers, ~ one_enhead(.x, sheet_data = sheet_data, table_spec = table_1)) %>% reduce(full_join)

    list(
    tidy_table_list = full_table %>% group_by(row_number()) %>% nest() %>% pull(data) %>% map(as.list),
    meta_data_list = meta_data_list
    ) 

    }) 

    sheet_data <- sheet_df %>% mutate(.value = coalesce(character,as.character(numeric),as.character(date),as.character(logical))) %>% select(row,col,address,.value)
    meta_data_list <- spec_ls[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>%flatten()

list(
    sheet_metata =  meta_data_list, 
    tables =  processed_tables
) 


#--------------------------------------------------------
library(tidyverse)


list.files("./R", full.names = T)  %>% map(source)



source_metadata_df <- read_csv("source_metadata.csv")

function(source_metadata_df, sha_current ){

    sheet_metadata_df <-  source_metadata_df %>% filter(sheet_sha256 == sha)

    xlsx_path = paste0("./source-spreadsheets-xlsx/",sheet_metadata_df$xlsx_file)

    spec_ls <- jsonlite::read_json(paste0("./tidy-recipes/" , sheet_metadata_df$sheet_sha256, ".json"))
    sheet_df <- tidyxl::xlsx_cells(path = xlsx_path, sheets = sheet_metadata_df$sheet_index)

    table_ls <- spec_ls[["tables"]]

    processed_tables <- 
        table_ls %>% map(function(table_1){

        sheet_data <- sheet_df %>% mutate(.value = coalesce(character,as.character(numeric),as.character(date),as.character(logical))) %>% select(row,col,address,.value)
        meta_data_list <- table_1[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>%flatten()
        full_table <- map(table_1$headers, ~ one_enhead(.x, sheet_data = sheet_data, table_spec = table_1)) %>% reduce(full_join)

        list(
        tidy_table_list = full_table %>% group_by(row_number()) %>% nest() %>% pull(data) %>% map(as.list),
        meta_data_list = meta_data_list
        ) 

        }) 

        sheet_data <- sheet_df %>% mutate(.value = coalesce(character,as.character(numeric),as.character(date),as.character(logical))) %>% select(row,col,address,.value)
        meta_data_list <- spec_ls[["meta_data"]] %>% map(function(list){list2(!!sym(list[["name"]]) := sheet_data %>% filter(address %in% expand_excel_range(list[["cells"]])) %>% pull(.value))}) %>%flatten()

return(
    list(
        sheet_metata =  meta_data_list, 
        tables =  processed_tables
    ) 
)

}