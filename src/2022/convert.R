library("tidyverse")
library("arrow")
library("haven")

source("src/helpers/helpers.R")

cli_h1('PISA 2022')

cli_progress_step("Load data")

IDENTIFIERS <- c("cntstuid")

# unfortunately, `unz` and `unzip` cannot unzip the very large student files on the fly,
# so we have to create temporary files for them instead and use the OS unzip utility;
# this may take a while and it will take up a couple of gigabytes of storage space so
# beware if you have a full drive
files <- tempfile()
unzip("data/2022/STU_QQQ_SPSS.zip", exdir = files, unzip = "/usr/bin/unzip")

# the SPSS files are nicer to work with than the SAS ones, in particular
# they support factor labels and missingness labels for numeric columns
raw <- read_sav(file.path(files, "CY08MSP_STU_QQQ.sav"), user_na = TRUE)
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

# check whether extraction of missingness flags worked as intended
sniff_sentinels(processed)




#### Identifiers ####

# keep the original country identification codes before converting to factors
processed$country_iso <- remove_labels(raw$cnt)
processed$country_id <- remove_labels(raw$cntryid)
processed$stratum_id <- remove_labels(raw$stratum)



#### Factors ####

# convert "labeled numbers" into either true factors
# or unlabeled numeric vectors
processed <- labelled_to_factors(processed)
processed <- unlabel_numbers(processed)




#### Save dataset ####

cli_progress_step("Write to parquet dataset")

write_parquet(processed, "build/2022.parquet",
  compression = "zstd", compression_level = 10
)

write_parquet(flags, "build/flags/2022.parquet",
  compression = "zstd", compression_level = 10
)

cli_progress_done()
