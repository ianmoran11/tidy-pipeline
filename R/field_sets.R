# Base intersect() and setdiff() are too slow for code that runs on every record, which
# calls them tens of millions of times in a rebuild. These give the same result for
# vectors without duplicates, such as field names, and keep x's order.
in_both <- function(x, y) x[x %in% y]
not_in <- function(x, y) x[!x %in% y]
