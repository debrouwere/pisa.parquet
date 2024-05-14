library("tidyverse")
library("arrow")
library("haven")
library("cli")

source("src/helpers/helpers.R")

cli_h1('PISA 2003')

cli_progress_step("Load data")

IDENTIFIERS <- c("country", "schoolid", "stidstd")

positions <- read_csv("src/2003/student/positions.csv")
labels <- read_csv("src/2003/student/labels.csv")
factors <- read_csv("src/2003/student/factors.csv")
levels <- read_csv("src/2003/student/levels.csv")

# when not using the fwf_positions function, read_fwf positions
# should be encoded as (begin - 1, end), presumably so that
# end - begin corresponds to the column width
positions$begin <- positions$begin - 1

# lowercase column names and factor level definitions
positions$col_names <- str_to_lower(positions$col_names)
factors$factor <- str_to_lower(factors$factor)
factors$levels <- str_to_lower(factors$levels)
levels$column <- str_to_lower(levels$column)

raw <- read_fwf("data/2003/pisa-int-stui.zip", col_positions = positions)
processed <- raw

cli_progress_done()




#### Sentinels ####

# split up every column into one containing only actual values
# and another containing only sentinel values
#
# TODO: do some custom preprocessing of "weird columns" like stratum
# that can have a missingness suffix instead of a full-column missingness code

extracted <- extract_flags(
  data = processed,
  metadata = processed |> select(all_of(IDENTIFIERS)),
  colspecs = positions,
  suffixes = 7:9
)
processed <- extracted$data
flags <- extracted$metadata

# check whether sentinels were successfully extracted
sniff_sentinels(processed, treshold = 10)



#### Identifiers ####

# keep the original country identification codes before converting to factors
processed$country_iso <- processed$cnt
processed$country_id <- processed$country
processed$stratum_id <- processed$stratum



#### ESCS ####

cli_progress_step("Merge backported ESCS scale")

# PISA 2003 does not contain an ESCS measure but does contain all of its components;
# the ESCS measure was later backported to allow for easier comparison between editions
escs <- read_sas("data/trend_escs/escs_2003.sas7bdat")
processed <- left_join(processed, escs, by = c("cnt", "schoolid", "stidstd"))

cli_progress_done()




#### Errata, manual conversions etc. ####

# all numeric columns are floats, but some ought to be integers
print("Downcasting floats to integers wherever appropriate")

integers <- c(
  "st02q02", # birth month
  "st02q03", # birth year
  "st01q01", # grade
  "mmins", # minutes per week in math
  "tmins" # minutes per week, all instructional time
)

for (integer in integers) {
  processed[, integer] <- as.integer(processed[[integer]])
}




#### Factors ####

# some of the "factors" for which levels are defined
# actually only define missingness codes, and these should not
# be treated as factors

print("Detecting factor variables")

factors <- annotate_pseudofactors(factors, levels)
true_factors <- factors %>% filter(is_factor == TRUE)

# the level definitions for `langn` do not include all codes that are present,
# but it is nevertheless a true factor
observed_langn <- na.omit(unique(processed$langn))
expected_langn <- levels[levels$column == "langn", ]$key
setdiff(observed_langn, expected_langn)
factors[factors$factor == "langn", "is_factor"] <- TRUE

# convert numerical factor codes into factors with levels and labels

processed <- chars_to_factors(processed, true_factors, levels)



#### Save dataset ####

cli_progress_step("Write to parquet dataset")

write_parquet(processed, "build/2003.parquet",
  compression = "zstd", compression_level = 10
)

write_parquet(flags, "build/flags/2003.parquet",
  compression = "zstd", compression_level = 10
)

cli_progress_done()
