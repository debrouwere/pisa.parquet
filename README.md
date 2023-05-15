# pisa.parquet

The Programme for International Student Assessment (PISA) is a large-scale educational test of students' aptitude in mathematics, science and reading literacy, administered worldwide to 15 year old students every three years and coordinated by the Organisation for Economic Co-operation and Development (OECD).

On its website, anonymized data can be downloaded in fixed-width, SPSS and SAS formats, which is inconvenient to work with for researchers who prefer to work in R or Python and slow to load. `pisa.parquet` provides a preprocessed PISA dataset that is faster, more convenient and more uniform to work with than the raw datasets provided by the OECD.

### Features

Fast:

* incredibly fast reads: because Parquet stores and compresses data column by column, reading in a subset of columns is extremely fast; because data is partitioned by country, so is reading in data for only a single participant country
* a single dataset that merges student, school, parent and cognitive data: due to the large amount of data these joins are computationally expensive and it's easy to run out of memory, so we've taken care of this

Convenient:

* human-readable column labels
* descriptive factor levels
* snake_cased descriptive column names instead of numbered questions like `st01q01`

Uniform:

* separation of sentinel values (valid skip, not reached, not applicable, invalid, non response, system missing) into their own columns so they are never accidentally treated as real data
* (limited) harmonization of data across editions: e.g. mother's main job is `st09q01` in PISA 2000 and `st07q01` in PISA 2003, both of which correspond to `mothers_main_job` in the Parquet dataset; we've included a compendium so you can figure out where to find the variables you're looking for

Complete:

* the dataset contains PISA 2000 through 2018
* whenever possible, we've merged in additional data files, additional questionnaires and backported rescaled items
* (limited) connections to other datasets, e.g. country-level OECD data about gross domestic product (GDP), social spending, educational spending and so on

### Usage

```r
install.packages('arrow')

library('tidyverse')
library('arrow')

# load the whole damn thing (not recommended)
pisa <- open_dataset('pisa.parquet', partitioning='country') %>% collect()

# preselect the data you are interested in
pisa2000 <- open_dataset('pisa.parquet', partitioning='country') %>% 
  select(c(starts_with('pv'), starts_with('w_'), 'escs', 'grade', 'gender')) %>% 
  filter(country == 'Belgium', year == 2000) %>%
  collect()
```

When working with large datasets in CSV or FWF format, it is common to read in the entire dataset even if you need only a handful of columns, which uses a lot of memory but avoids having to wait endless minutes while reading in the data yet again if you decide you need to include an additional column or two. However, reading in Parquet data is nearly instantaneous so you will work faster and use less memory if you preselect the data you need while reading it in.

### Benchmarks

Well, it's fast!
