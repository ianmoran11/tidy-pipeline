# Evidence for the court-level mapping of the 2009–10 and 2010–11 Criminal Courts cubes,
# which name their court level only in the cube code (measures/measure_spec.json
# title_flags). Series are compared without court_level, population and scope.
#   1. Additivity, 2009–10: cube 2 + cube 3 + cube 4 = cube 5 (all courts)?
#   2. 2009–10 cubes 6–8 against 2010–11 tables that name their court level in the title.
# Expected: 2 and 6 = Higher, 3 and 7 = Magistrates', 4 and 8 = Children's Courts.
suppressMessages({library(dplyr); library(stringr); library(tidyr)})
obs <- targets::tar_read(observations); it <- targets::tar_read(integrated); src <- it$sources; ser <- it$series
dims <- setdiff(names(ser), c("series_id", "measure_id", "court_level", "population", "scope"))
ser$key <- do.call(paste, c(as.list(ser[dims]), sep = "|"))
x <- obs %>% filter(value_status == "published") %>% left_join(src %>% select(sheet_sha256, xlsx_file, title), by = "sheet_sha256") %>%
  mutate(rel = str_match(xlsx_file, "criminal-courts-australia-(2009-10|2010-11)-cube-([0-9]+)-")[, 2],
         cube = str_match(xlsx_file, "criminal-courts-australia-(2009-10|2010-11)-cube-([0-9]+)-")[, 3]) %>%
  filter(!is.na(cube)) %>% left_join(ser %>% select(series_id, key, measure), by = "series_id")

w <- x %>% filter(rel == "2009-10", cube %in% c("2", "3", "4", "5"), toupper(measure) == "NUMBER") %>%
  group_by(key, period, cube) %>% summarise(v = first(value), .groups = "drop") %>%
  pivot_wider(names_from = cube, values_from = v, names_prefix = "c") %>% filter(!is.na(c2), !is.na(c3), !is.na(c4), !is.na(c5))
cat("1. 2009–10 cells in cubes 2-5:", nrow(w), "| c2 + c3 + c4 = c5:", sum(w$c2 + w$c3 + w$c4 == w$c5),
    "| c2 <= c3:", sum(w$c2 <= w$c3), "| c4 <= c3:", sum(w$c4 <= w$c3), "\n")

titled <- x %>% filter(rel == "2010-11", str_detect(title, regex("HIGHER COURTS|MAGISTRATES' COURTS|CHILDREN'S COURTS", ignore_case = TRUE))) %>%
  mutate(level = str_to_title(str_extract(title, regex("HIGHER COURTS|MAGISTRATES' COURTS|CHILDREN'S COURTS", ignore_case = TRUE)))) %>%
  select(level, key, period, v_new = value)
old <- x %>% filter(rel == "2009-10", cube %in% c("6", "7", "8")) %>% select(cube, key, period, v_old = value)
cat("2. 2009–10 cubes 6-8 vs 2010-11 tables naming their court level (equal values):\n")
print(inner_join(old, titled, by = c("key", "period"), relationship = "many-to-many") %>% group_by(cube, level) %>%
  summarise(pairs = n(), equal = sum(v_old == v_new), .groups = "drop") %>% group_by(cube) %>% mutate(share = round(equal / sum(equal), 2)) %>% arrange(cube, desc(equal)))
