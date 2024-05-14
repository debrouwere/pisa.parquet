library("tidyverse")
library("arrow")
library("haven")

source("src/helpers.R")

cli_progress_step("Load data")

IDENTIFIERS <- c("cntstuid")

# unfortunately, `unz` and `unzip` cannot unzip the very large student files on the fly,
# so we have to create temporary files for them instead and use the OS unzip utility;
# this may take a while and it will take up a couple of gigabytes of storage space so
# beware if you have a full drive
files <- tempfile()
unzip("data/2015/PUF_SPSS_COMBINED_CMB_STU_QQQ.zip", exdir = files, unzip = "/usr/bin/unzip")

# the SPSS files are nicer to work with than the SAS ones, in particular
# they support factor labels and missingness labels for numeric columns
raw <- read_sav(file.path(files, "CY6_MS_CMB_STU_QQQ.sav"), user_na = TRUE)
colnames(raw) <- str_to_lower(colnames(raw))

unlink(files, recursive = TRUE)

processed <- raw

cli_progress_done()




#### Sentinels ####

# extract colwidths and check if all colwidths were successfully extracted from the spss formats,
# then split up every column into one containing only actual values and another containing
# only sentinel values
colwidths <- spss_formats_to_colwidths(raw)

extracted <- extract_flags(
  data = processed,
  metadata = processed |> select(all_of(IDENTIFIERS)),
  colspecs = colwidths,
  suffixes = 5:9
)
processed <- extracted$data
flags <- extracted$metadata

# check whether sentinels were successfully extracted
problems <- sniff_sentinels(processed, treshold = 10)
write_csv(problems, 'build/2015/problems/flags/students.csv')




#### Identifiers ####

# keep the original country identification codes before converting to factors
processed$country_iso <- remove_labels(raw$cnt)
processed$country_id <- remove_labels(raw$cntryid)
processed$stratum_id <- remove_labels(raw$stratum)



#### Errata, manual conversions etc. ####

cli_progress_step("Downcast floats to integers wherever appropriate")

integers <- c(
  "bookid",
  "st001d01t", # grade
  "st003d02t", # birth month
  "st003d03t", # birth year
  "mmins",
  "lmins",
  "smins",
  "tmins",
  "change",
  "icthome",
  "ictsch"
)

for (integer in integers) {
  processed[, integer] <- as.integer(processed[[integer]])
}

cli_progress_done()




#### Factors ####

# convert "labeled numbers" into either true factors
# or unlabeled numeric vectors
processed <- labelled_to_factors(processed)
processed <- unlabel_numbers(processed)




#### Save dataset ####

cli_progress_step("Write to parquet dataset")

write_parquet(processed, "build/2015/students.parquet",
              compression = "zstd", compression_level = 10
)

write_parquet(flags, "build/2015/flags/students.parquet",
              compression = "zstd", compression_level = 10
)

cli_progress_done()
