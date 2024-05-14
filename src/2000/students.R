library("tidyverse", quiet = TRUE)
library("arrow")
library("haven")
library("cli")

source("src/helpers.R")

cli_progress_step("Load data")

IDENTIFIERS <- c("country", "schoolid", "stidstd")

positions <- read_csv("src/2000/student/reading/positions.csv")
labels <- read_csv("src/2000/student/reading/labels.csv")
factors <- read_csv("src/2000/student/reading/factors.csv")
levels <- read_csv("src/2000/student/reading/levels.csv")

# when not using the fwf_positions function, read_fwf positions
# should be encoded as (begin - 1, end), presumably so that
# end - begin corresponds to the column width
positions$begin <- positions$begin - 1

# lowercase column names and factor level definitions
positions$col_names <- str_to_lower(positions$col_names)
factors$factor <- str_to_lower(factors$factor)
factors$levels <- str_to_lower(factors$levels)
levels$column <- str_to_lower(levels$column)

# add in plausible values for reading and science from separate files
positions_math <- read_csv("src/2000/student/mathematics/positions.csv")
positions_math$begin <- positions_math$begin - 1
positions_math$col_names <- str_to_lower(positions_math$col_names)
positions_scie <- read_csv("src/2000/student/science/positions.csv")
positions_scie$begin <- positions_scie$begin - 1
positions_scie$col_names <- str_to_lower(positions_scie$col_names)

# PISA 2000 requires different student weights for math, science and reading
# (later editions use a single weight that is valid for all subjects)
raw_read <- read_fwf("data/2000/pisa-intstud-read.zip", col_positions = positions)
raw_math <- read_fwf("data/2000/pisa-intstud-math.zip", col_positions = positions_math, col_select = c("country", "schoolid", "stidstd", "subnatio", "wlemath", "wlerr_m", matches("pv\\dmath\\d?"), starts_with("w_"), "cntmfac", "math_waf"))
raw_scie <- read_fwf("data/2000/pisa-intstud-scie.zip", col_positions = positions_scie, col_select = c("country", "schoolid", "stidstd", "subnatio", "wlescie", "wlerr_s", starts_with("pv") & ends_with("scie"), starts_with("w_"), "cntsfac", "scie_waf"))

# disambiguate column names
colnames(raw_read) <- str_replace(colnames(raw_read), "w_", "w_read_")
colnames(raw_math) <- str_replace(colnames(raw_math), "w_", "w_math_")
colnames(raw_scie) <- str_replace(colnames(raw_scie), "w_", "w_scie_")

# merge back formatting information for renamed variables
# (will be used later for parsing numbers and extracting flags)
extra_cols <- c(colnames(raw_math)[c(-1, -2, -3, -4)], colnames(raw_scie)[c(-1, -2, -3, -4)])

positions_x_math <- positions_math |> filter(col_names %in% extra_cols)
positions_x_scie <- positions_scie |> filter(col_names %in% extra_cols)

positions_w_read <- positions_w_math <- positions_w_scie <- positions |> filter(str_starts(col_names, "w_"))
positions_w_read$col_names <- str_replace(positions_w_read$col_names, "w_", "w_read_")
positions_w_math$col_names <- str_replace(positions_w_math$col_names, "w_", "w_math_")
positions_w_scie$col_names <- str_replace(positions_w_scie$col_names, "w_", "w_scie_")
positions <- rbind(positions, positions_w_read, positions_x_math, positions_w_math, positions_x_scie, positions_w_scie)

cli_progress_done()

cli_progress_step("Merge reading, mathematics and science datasets")

# merge reading, mathematics and science datasets
raw <- full_join(raw_read, raw_math, by = c(IDENTIFIERS, "subnatio"))
raw <- full_join(raw, raw_scie, by = c(IDENTIFIERS, "subnatio"))

processed <- raw

cli_progress_done()


#### Sentinels ####

# split up every column into one containing only actual values
# and another containing only sentinel values
#
# because sentinels are always an order of magnitude larger than
# real values in the data, we can run through this process without
# accidentally interpreting real data as sentinels
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
problems <- sniff_sentinels(processed, treshold = 10)
write_csv(problems, 'build/2000/problems/flags/students.csv')




#### Identifiers ####

# keep the original country identification codes before converting to factors
processed$country_iso <- processed$cnt
processed$country_id <- processed$country
processed$stratum_id <- str_sub(processed$schoolid, 1, 2)



#### ESCS ####

# PISA 2000 does not contain an ESCS measure but does contain all of its components;
# the ESCS measure was later backported to allow for easier comparison between editions
cli_progress_step("Merge backported ESCS scale")

escs <- read_sas("data/trend_escs/escs_2000.sas7bdat")
processed <- left_join(processed, escs, by = c("cnt", "schoolid", "stidstd"))

cli_progress_done()




#### Errata, manual conversions etc. ####

# bizarrely, and only for the math subscales, the character "." was used in addition to `NA`
# to represent missing data, perhaps to differentiate between missing by design (randomly
# chosen not to do the math subtest) and missing by participation (country exemption) or
# something similar; note that the 9997 missingness code from the codebook is *not* used

processed <- processed |> mutate(across(
  ends_with("math1") | ends_with("math2"),
  ~ as.numeric(na_if(.x, "."))
))

#sum(is.na(raw$pv1math1))
#sum(raw$pv1math1 == ".", na.rm = TRUE)
#max(raw$pv1math1, na.rm = TRUE)

#sum(is.na(processed$pv1math1))
#sum(processed$pv1math1 == ".", na.rm = TRUE)
#max(processed$pv1math1, na.rm = TRUE)

# cc01q01, a question from the cross-cultural competencies questionnaire
# that reads "When I study, I try to memorise everything that might be covered."
# contains two values of 5, which makes no sense.
#
#  * 4 means "always" and cannot be trumped
#  * 5 as a flag means "valid skip" but this is not an option according to
#    the codebook and the question ought to apply to everyone
#
# We'll recode these as 8 (invalid).

n_invalid <- sum(processed$cc01q01 == 5, na.rm = TRUE)
cli_progress_step("Recoding {n_invalid} invalid values in cc01q01 from #5 to #8")
processed <- processed |>
  mutate(cc01q01 = if_else(cc01q01 == 5, 8, cc01q01))

# all numeric columns are floats, but some ought to be integers
cli_progress_step("Downcasting floats to integers wherever appropriate")

integers <- c(
  "st01q02", # birth month
  "st01q03", # birth year
  "age", # age in months
  "st02q01", # grade
  "rmins", # minutes per week in language
  "mmins", # minutes per week in math
  "smins", # minutes per week in science
  "nsib", # number of siblings
  "brthord" # birth order
)

for (integer in integers) {
  processed[, integer] <- as.integer(processed[[integer]])
}




#### Factors ####

# some of the "factors" for which levels are defined
# actually only define missingness codes, and these should not
# be treated as factors

cli_progress_step("Detect factor variables")

factors <- annotate_pseudofactors(factors, levels)
true_factors <- factors |> filter(is_factor == TRUE)

# convert numerical factor codes into factors with levels and labels

processed <- chars_to_factors(processed, true_factors, levels)

cli_progress_done()

#### Save dataset ####

cli_progress_step("Write to parquet dataset")

write_parquet(processed, "build/2000/students.parquet",
              compression = "zstd", compression_level = 10
)

write_parquet(flags, "build/2000/flags/students.parquet",
              compression = "zstd", compression_level = 10
)

cli_progress_done()
