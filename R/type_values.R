# Stage 6: the published text as a number plus a status. Symbols such as "np", ".."
# and "–" are looked up for the observation's publication, then under "default";
# their spec entry gives the status and, where the symbol means a number (nil or
# rounded to zero), the value. Empty cells get the blank status. Text that is
# neither a number nor a known symbol is "unrecognised". See integration/README.md.
type_values <- function(observations, sources, value_spec) {
  spec <- value_spec
  symbols <- purrr::imap_dfr(spec$symbols, function(s, p) tibble::tibble(publication_id = p, text = names(s),
    status = purrr::map_chr(s, "status"), value = purrr::map_dbl(s, ~ as.numeric(.x[["value"]] %||% NA))))
  pub <- sources$publication_id[match(observations$sheet_sha256, sources$sheet_sha256)]
  text <- stringr::str_squish(observations$published_text)
  number <- suppressWarnings(as.numeric(gsub(",", "", text)))
  i <- dplyr::coalesce(match(paste(pub, text), paste(symbols$publication_id, symbols$text)),
                       match(paste("default", text), paste(symbols$publication_id, symbols$text)))
  observations$value <- dplyr::if_else(is.na(number), symbols$value[i], number)
  observations$value_status <- dplyr::case_when(is.na(text) | text == "" ~ spec$blank_status, !is.na(number) ~ spec$number_status,
                                                !is.na(i) ~ symbols$status[i], TRUE ~ "unrecognised")
  observations
}
