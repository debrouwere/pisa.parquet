# pisa.parquet

The Programme for International Student Assessment (PISA) is a large-scale educational test of students' aptitude in mathematics, science and reading literacy, administered worldwide to 15 year old students every three years and coordinated by the Organisation for Economic Co-operation and Development (OECD).

On its website, anonymized data can be downloaded in fixed-width, SPSS and SAS formats, which is inconvenient to work with for researchers who prefer to work in R or Python, and it is slow to load. `pisa.parquet` provides a PISA dataset that takes up less space and is faster to work with than the raw datasets provided by the OECD.

Currently, only the student datasets are available. The school, parent and cognitive datasets will be added at a later date.

### Features

`pisa.parquet` stays very close to the original dataset and does not aim to clean or otherwise preprocess the data, but does provide a handful of minor conveniences over the published datasets:

* lower-cased column names
* backported ESCS data
* combination of the individual literacy, math and science datasets from PISA 2000
* categorical variables with human-readable labels instead of numeric codes
* ... though we also retain the original codes for important identifiers; these are available as additional columns `country_iso`, `country_id` and `stratum_id`
* extraction of sentinel values that indicate missingness (e.g. `999999`) to separate `flags/{cycle}.parquet` datasets where they don't mess with calculations

`pisa.parquet` is also the starting point for [pisa.rx.parquet](https://github.com/debrouwere/pisa.rx.parquet), a harmonized dataset that corrects for the many small discrepancies between the questionnaires of different assessment cycles. `pisa.rx.parquet` allows for repeat cross-sectional analyses from 2000 to 2022.

### Usage

```r
install.packages(c("tidyverse", "arrow"))

library("tidyverse")
library("arrow")

# load the whole damn thing (not recommended)
pisa <- open_dataset("build/2022.parquet") |> collect()

# preselect the data you are interested in
pisa <- open_dataset('build/2022.parquet') |> 
  select(starts_with('pv'), starts_with('w_'), escs, grade, gender) |> 
  filter(country == 'Belgium') |> 
  collect()
```

When working with large datasets in comma-separated or fixed-width format, it is common to read in the entire dataset even if you need only a handful of columns, which uses a lot of memory but avoids having to wait endless minutes while reading in the data again and again when you inevitably end up needing an additional column here and there. However, because reading in Parquet data is nearly instantaneous, you will work faster and use less memory if you preselect only the columns you need (`select`) and the rows you need (`filter`) while reading it in.

### Build

```sh
export PISA_BUILD_SERVER=...
export PISA_REMOTE_PATH=...
make update
make build
```
