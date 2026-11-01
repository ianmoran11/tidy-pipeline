# HISTORY ONLY: not part of the workflow. This built the first version of the sheet
# inventory (source_metadata.csv) from the original package metadata and the SQLite
# tables. Its output, with publisher URL fields added later, is pinned as
# sources/catalogues/current_pipeline.csv. source_metadata.csv is now written by
# get_source_data.R. Rerunning this would not reproduce the URL fields.

library(tidyverse)
library(stringr)
library(tidyxl)
library(jsonlite)
library(DBI)
library(RSQLite)


# Active workbooks, plus redundant copies archived in reference-only/
source_data_df <- 
    c(list.files("./source-spreadsheets-xlsx", full.names = T),
      list.files("./source-spreadsheets-xlsx/reference-only", full.names = T)) %>%
    keep(~ str_detect(.x,"\\.xlsx$") & !str_starts(basename(.x), fixed("~$"))) %>%   # skip Excel lock files
    tibble(xlsx_path = . )

source_data_df_01 <- 
source_data_df %>%
  mutate(sheets = map(xlsx_path, tidyxl::xlsx_sheet_names))

source_data_df_02 <-  source_data_df_01 %>% unnest(sheets)


# Source-level metadata --------------------------------------------------------
# File name hash prefixes and source_sha256 identify the ORIGINAL source bytes,
# not the converted XLSX bytes.

metadata_dir <- "./source-spreadsheets-xlsx/original-package-metadata"

collapse_unique <- function(x) {
  x <- sort(unique(na.omit(x)))
  if (length(x) == 0) NA_character_ else str_flatten(x, "; ")
}

# Original file -> XLSX copy
conversion_map <-
  read_csv("./source-spreadsheets-xlsx/conversion-map.csv",
           col_types = cols(.default = col_character())) %>%
  transmute(
    xlsx_file = output_path,
    source_sha256,
    source_file = basename(source_path),
    source_format = tools::file_ext(source_path),
    xlsx_sha256 = output_sha256,
    conversion_operation = operation,
    vba_removed = as.logical(vba_removed)
  )

# Every direct reference from a database row to an original file
database_refs <-
  read_csv(file.path(metadata_dir, "database-references.csv"),
           col_types = cols(.default = col_character())) %>%
  mutate(source_sha256 = str_remove(sha256, "^sha256:"),
         byte_length = as.integer(byte_length))

file_refs <-
  database_refs %>%
  group_by(source_sha256) %>%
  summarise(
    database_tables = collapse_unique(database_table),
    publication_id = first(na.omit(publication_id)),
    source_release_id = first(na.omit(source_release_id)),
    cohort_ids = collapse_unique(cohort_id),
    normalization = collapse_unique(normalization),
    .groups = "drop"
  )

library(jsonlite)
# Recorded normalization relationships: upstream original -> normalized output
manifest <- read_json(file.path(metadata_dir, "manifest.json"), simplifyVector = TRUE)

source_byte_lengths <-
  with(manifest$files,
       tibble(source_sha256 = str_remove(sha256, "^sha256:"),
              source_byte_length = as.integer(byteLength)))

normalization_links <-
  with(manifest$normalizationRelationships,
       tibble(source_sha256 = str_remove(sourceSha256, "^sha256:"),
              output_sha256 = str_remove(outputSha256, "^sha256:"),
              in_range_values_changed = registryInRangeValuesChanged))

# Files with no direct database reference are normalization inputs; describe
# them using the database references of their normalized output.
metadata_sha <-
  conversion_map %>%
  distinct(source_sha256) %>%
  left_join(normalization_links %>%
              filter(!source_sha256 %in% file_refs$source_sha256) %>%
              group_by(source_sha256) %>%
              summarise(metadata_sha256 = first(output_sha256), .groups = "drop"),
            by = "source_sha256") %>%
  mutate(metadata_sha256 = coalesce(metadata_sha256, source_sha256))

normalized_to <-
  normalization_links %>%
  group_by(source_sha256) %>%
  summarise(normalized_to_sha256 = collapse_unique(output_sha256), .groups = "drop")

# Redundant copies kept for reference only, and the active workbook each duplicates
reference_copies <-
  read_csv("./source-spreadsheets-xlsx/reference-only/reference-only.csv",
           col_types = cols(.default = col_character())) %>%
  transmute(xlsx_file, reference_copy_type = copy_type, active_sha256)

normalized_from <-
  normalization_links %>%
  group_by(source_sha256 = output_sha256) %>%
  summarise(normalized_from_sha256 = collapse_unique(source_sha256),
            in_range_values_changed = any(in_range_values_changed),
            .groups = "drop")

library(DBI)
library("RSQLite")

# Publication, release, and accepted-asset details from the SQLite release
con <- dbConnect(SQLite(), "./tidy-data-asset-status.sqlite3", flags = SQLITE_RO)

publications <-
  dbGetQuery(con, "
    SELECT publication_id, label AS publication, publisher, period_format
    FROM source_publication") %>%
  as_tibble()

releases <-
  dbGetQuery(con, "
    SELECT source_release_id, label AS release, reference_period,
           reference_date, release_date
    FROM source_release") %>%
  as_tibble() %>%
  mutate(across(c(reference_date, release_date), as.Date))

# Accepted releases have no source_release row; their period comes from asset
assets <-
  dbGetQuery(con, "
    SELECT DISTINCT substr(source_digest, 8) AS source_sha256,
           publication_id, year, reference_date
    FROM asset") %>%
  as_tibble() %>%
  group_by(source_sha256) %>%
  summarise(asset_publication_id = first(publication_id),
            asset_year = first(year),
            asset_reference_date = as.Date(first(reference_date)),
            .groups = "drop")

dbDisconnect(con)

source_metadata_df <-
  conversion_map %>%
  left_join(metadata_sha, by = "source_sha256") %>%
  left_join(file_refs, by = c("metadata_sha256" = "source_sha256")) %>%
  left_join(source_byte_lengths, by = "source_sha256") %>%
  left_join(assets, by = c("metadata_sha256" = "source_sha256")) %>%
  left_join(releases, by = "source_release_id") %>%
  mutate(publication_id = coalesce(publication_id,
                                   asset_publication_id,
                                   str_remove(source_release_id, "::.*$"))) %>%
  select(-asset_publication_id) %>%
  left_join(publications, by = "publication_id") %>%
  left_join(normalized_to, by = "source_sha256") %>%
  left_join(normalized_from, by = "source_sha256") %>%
  left_join(reference_copies, by = "xlsx_file") %>%
  mutate(referenced_in_database = source_sha256 %in% file_refs$source_sha256,
         reference_only = !is.na(reference_copy_type)) %>%
  select(xlsx_file, source_sha256, source_file, source_format, source_byte_length,
         xlsx_sha256, conversion_operation, vba_removed,
         publication_id, publication, publisher, period_format,
         source_release_id, release, reference_period, reference_date, release_date,
         asset_year, asset_reference_date, cohort_ids,
         referenced_in_database, database_tables, normalization,
         normalized_from_sha256, normalized_to_sha256, in_range_values_changed,
         metadata_sha256, reference_only, reference_copy_type, active_sha256)

options(width = 180)

source_data_df_03 <-
  source_data_df_02 %>%
  mutate(xlsx_file = basename(xlsx_path)) %>%
  left_join(source_metadata_df, by = "xlsx_file")

source_data_df_03 %>%
 glimpse()


# Sheet-level ID ---------------------------------------------------------------
# sheet_key is "<source_sha256>/<exact sheet name>". Sheet names cannot contain
# "/" and are unique within a workbook, so the key is unique. sheet_sha256 is
# the SHA-256 of the UTF-8 bytes of sheet_key, so other tools can recompute it.

source_data_df_04 <-
  source_data_df_03 %>%
  group_by(xlsx_path) %>%
  mutate(sheet_index = row_number()) %>%
  ungroup() %>%
  mutate(
    sheet_key = paste0(source_sha256, "/", enc2utf8(sheets)),
    sheet_sha256 = map_chr(sheet_key, digest::digest, algo = "sha256", serialize = FALSE),
    # Reference-only copies point to the same sheet of the workbook they duplicate
    active_sheet_sha256 = if_else(reference_only,
                                  map_chr(paste0(active_sha256, "/", enc2utf8(sheets)), digest::digest, algo = "sha256", serialize = FALSE),
                                  NA_character_)
  ) %>%
  relocate(sheet_sha256, sheet_key, sheet_index, .after = sheets)

stopifnot(!anyDuplicated(source_data_df_04$sheet_sha256))
stopifnot(all(na.omit(source_data_df_04$active_sheet_sha256) %in% source_data_df_04$sheet_sha256))

