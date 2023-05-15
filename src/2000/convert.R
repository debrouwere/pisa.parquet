library('tidyverse')
library('arrow')

positions <- read_csv('student/mathematics/positions.csv')
labels <- read_csv('student/mathematics/labels.csv')
factors <- read_csv('student/mathematics/factors.csv')
levels <- read_csv('student/mathematics/levels.csv')

# when not using the fwf_positions function, read_fwf positions 
# should be encoded as (begin - 1, end), presumably so that
# end - begin corresponds to the column width
positions$begin <- positions$begin - 1

raw <- read_fwf('../data/2000/pisa-intstud-math.zip', col_positions=positions)

widths <- as.list(positions$end - positions$begin)
names(widths) <- positions$col_names

processed <- raw

#### Errata, manual conversions etc. ####

# cc01q01, a question from the cross-cultural competencies questionnaire
# that reads "When I study, I try to memorise everything that might be covered."
# contains two values of 5, which makes no sense.
#
#  * 4 means "always" and cannot be trumped
#  * 5 as a flag means "valid skip" but this is not an option according to
#    the codebook and the question ought to apply to everyone
#
# We'll recode these as 8 (invalid).

n_invalid <- sum(processed$cc01q01 == 5)
print(str_glue('Recoding {n_invalid }invalid values in cc01q01 from #5 to #8'))
processed[processed$cc01q01 == 5, 'cc01q01'] <- 8


# PISA 2000 does not contain an ESCS measure but does contain all of its components;
# the ESCS measure was later backported to allow for easier comparison between editions
print('Merging with backported ESCS data')
escs <- read_sas('data/trend_escs/escs_2000.sas7bdat')
processed <- left_join(processed, escs, by=c('cnt', 'schoolid', 'stidstd'))


# all numeric columns are floats, but some ought to be integers
print('Downcasting floats to integers wherever appropriate')

integers <- c(
  'st01q02', # birth month
  'st01q03', # birth year
  'age',     # age in months
  'st02q01', # grade
  'rmins',   # minutes per week in language
  'mmins',   # minutes per week in math
  'smins',   # minutes per week in science
  'nsib',    # number of siblings
  'brthord'  # birth order
)

for (integer in integers) {
  processed[, integer] <- as.integer(processed[[integer]])
}

#### Factors ####

# some of the "factors" for which levels are defined
# actually only define missingness codes, and these should not
# be treated as factors

print('Detecting factor variables')

levels$column <- str_to_lower(levels$column)
factors$factor <- str_to_lower(factors$factor)
factors$levels <- str_to_lower(factors$levels)
factors$is_factor <- TRUE

for (i in 1:nrow(factors)) {
  factor <- factors[i,]
  name <- factor$factor
  values <- processed[[name]]
  factor_levels <- levels[levels$column == factor$levels,]  
  
  k_expected <- nrow(factor_levels)
  k_observed <- length(unique(values))
  
  if (k_observed > k_expected) {
    print(str_glue('* Detected {name} pseudofactor: observed {k_observed} levels, expected {k_expected} levels'))
    
    factors[i, 'is_factor'] <- FALSE
  }
}

true_factors <- factors[factors$is_factor, ]

# split up every column into one containing only actual values
# and another containing only sentinel values
# 
# because sentinels are always an order of magnitude larger than
# real values in the data, we can run through this process without
# accidentally interpreting real data as sentinels
# 
# TODO: do some custom preprocessing of "weird columns" like stratum
# that can have a missingness suffix instead of a full-column missingness code

replace_values <- function(source, destination, matches, replacements) {
  for (i in 1:length(matches)) {
    match <- matches[i]
    replacement <- replacements[i]
    destination[source == match] <- replacement
  }
  
  destination
}

for (name in names(raw)) {
  print(str_glue('* Extracting flags for {name}'))
  values <- raw[[name]]
  values_as_strings <- as.character(values)
  name_flags <- str_glue('{name}_flags')
  width <- widths[[name]]
  codes <- sapply(5:9, function(code) { str_flatten(c(rep(9, width - 1), code)) })
  intents <- c('valid skip', 'not reached', 'not applicable', 'invalid', 'no response')
  blanks <- rep(NA, 5)
  processed[,name] <- replace_values(values_as_strings, values, codes, blanks)
  flags <- rep('acceptable', length(values))
  flags[is.na(values)] <- 'system missing'
  processed[,name_flags] <- as.factor(replace_values(values_as_strings, flags, codes, intents))
}

# convert numerical factor codes into factors with levels and labels

for (i in 1:nrow(true_factors)) {
  factor <- true_factors[i,]
  name <- str_to_lower(factor$factor)

  # we need the preprocessed values because we don't want
  # the missingness flags in there
  values <- processed[[name]]
  values_as_strings <- as.character(values)
  factor_levels <- levels[levels$column == factor$levels,]
  
  print(str_glue('* Converting {name} to factor'))
  values_as_factor <- factor(values_as_strings,
                             levels=factor_levels$key,
                             labels=factor_levels$value)    
  processed[,name] <- droplevels(values_as_factor)
}

# single dataset
write_parquet(processed, '../build/2000.parquet',
              compression='zstd', compression_level=10)

# partitioned dataset
write_dataset(group_by(processed, country), '../build/2000', 
              format='parquet', hive_style=FALSE,
              compression='zstd', compression_level=10)
