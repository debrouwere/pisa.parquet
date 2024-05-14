library("tidyverse", quiet = TRUE)
library("cli")
library("labelled")

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
#
# TODO: I'm guessing we don't need flags columns for plausible values and weights?

INTENTS <- c(
  NA,
  NA,
  NA,
  NA,
  "valid skip",
  "not reached",
  "not applicable",
  "invalid",
  "no response"
)

replace_values <- function(source, destination, matches, replacements) {
  for (i in 1:length(matches)) {
    match <- matches[i]
    replacement <- replacements[i]
    destination[source == match] <- replacement
  }
  destination
}

as_formatted_string <- function(x, frac_places) {
  coerced <- quietly(as.numeric)(x)$result
  format(coerced, nsmall = frac_places, trim = TRUE)
}

# NOTE: columns in older PISA datasets sometimes do not use their allotted
# width, so it is possible to have a column of width 10 with 3 whole places and
# 3 decimal places (plus the separator) -- an important difference when trying
# to figure out the missingness codes
#
# NOTE: `extract_flags` expects *every* column except those in
# `exclude_cols_pattern` to have an associated colspec, so this function must be
# run early in the conversion, before any additional columns have been added;
# perhaps we should iterate over the colspec instead to avoid this issue?
extract_flags <- function(data, metadata, colspecs, suffixes = 5:9, exclude_cols_pattern = "^(w_|.+waf|country_.+)", discard_cols_pattern = "^pv") {
  name <- ""
  cli_progress_step("Extract flags: {name}")

  # excluded columns are not processed at all, whereas discarded columns are
  # processed but the extracted flags are thrown out
  all_cols <- names(data)
  exclude_ixs <- all_cols |> str_detect(exclude_cols_pattern)
  discard_ixs <- all_cols |> str_detect(discard_cols_pattern)

  cols <- all_cols[!exclude_ixs]
  discard_cols <- all_cols[discard_ixs]

  for (name in cols) {
    is_discarded <- name %in% discard_cols
    is_discarded_desc <- ifelse(is_discarded, "(discarded)", "")

    cli_progress_update()

    values <- data[[name]]

    colspec <- colspecs |> filter(col_names == name)
    width <- colspec$width
    whole_places <- colspec$whole_places
    frac_places <- colspec$frac_places

    if (frac_places > 0) {
      # convert integers to floats if necessary, otherwise the nsmall argument is ignored
      values_as_strings <- as_formatted_string(values, frac_places)
      codes <- map_chr(suffixes, function(code) {
        str_c(strrep(9, whole_places - 1), code, ".", strrep(0, frac_places))
      })
    } else {
      values_as_strings <- as.character(values)
      codes <- map_chr(suffixes, function(code) {
        str_c(strrep(9, whole_places - 1), code)
      })
    }

    intents <- INTENTS[suffixes]
    blanks <- rep(NA, length(intents))
    data[, name] <- replace_values(
      source = values_as_strings,
      destination = values,
      matches = codes,
      replacements = blanks
    )

    if (!is_discarded) {
      flags <- rep("acceptable", length(values))
      flags[is.na(values)] <- "system missing"
      metadata[, name] <- as.factor(replace_values(
        source = values_as_strings,
        destination = flags,
        matches = codes,
        replacements = intents
      ))
    }
  }

  list(data = data, metadata = metadata)
}


# verify whether the extract_flags code did its job
#
# TODO: this works but not great, it may be better to (also)
# look for high density near the max value and very low density
# below that to represent the order-of-magnitude difference
# between real values and missingness codes
sniff_sentinels <- function(df, q1 = 0.25, q2 = 0.75, treshold = 10) {
  name <- ""
  progress <- cli_progress_step("Verify whether sentinels were successfully extracted: {name}")

  widths <- map(names(df), function(name) {
    values <- df[[name]]
    if (!is.numeric(values)) return()

    cli_progress_update(id = progress)

    iqr <- diff(quantile(values, c(q1, q2), na.rm = TRUE))
    iqr <- if_else(iqr < 1, 1, iqr)
    maximum <- max(values, na.rm = TRUE)
    minimum <- min(values, na.rm = TRUE)
    width <- maximum - minimum
    iqr_multiple <- iqr * treshold

    tibble(
      name = name,
      iqr = iqr,
      width = width,
      min = minimum,
      max = maximum,
      is_problem = iqr_multiple < width
    )
  })

  sniffed <- bind_rows(widths) |>
    mutate(across(where(is.numeric), \(x) round(x, 2))) |>
    arrange(desc(is_problem))
  n <- sniffed |> filter(is_problem) |> nrow()
  cli_alert_info("Detected very large values in {n} columns")
  sniffed
}


spss_formats_to_colwidths <- function(spss_df) {
  map_df(colnames(spss_df), function(colname) {
    fmt <- attr(spss_df[[colname]], "format.spss")
    width_and_places <- str_extract(fmt, "\\w(\\d+)(\\.(\\d))?", group = c(1, 3))
    width <- as.integer(width_and_places[1])
    frac_places <- ifelse(!is.na(width_and_places[2]), as.integer(width_and_places[2]), 0)
    is_fractional <- frac_places > 0
    whole_places <- width - (frac_places + is_fractional)
    list(
      col_names = colname,
      width = width,
      whole_places = whole_places,
      frac_places = frac_places
    )
  })
}


#### Factors ####

# some of the "factors" for which levels are defined
# actually only define missingness codes, and these should not
# be treated as factors

annotate_pseudofactors <- function(factors, levels) {
  levels$column <- str_to_lower(levels$column)
  factors$factor <- str_to_lower(factors$factor)
  factors$levels <- str_to_lower(factors$levels)
  factors$is_factor <- TRUE

  name <- k_observed <- k_expected <- '...'
  cli_progress_step("Detected {name} pseudofactor: observed {k_observed} levels, expected {k_expected} levels")
  for (i in 1:nrow(factors)) {
    factor <- factors[i, ]
    name <- factor$factor
    values <- processed[[name]]
    factor_levels <- levels[levels$column == factor$levels, ]

    k_expected <- nrow(factor_levels)
    k_observed <- length(na.omit(unique(values)))

    if (k_expected == 0) {
      cli_alert_danger("Level definitions not found for factor {name}")
    } else if (k_observed > k_expected) {
      cli_progress_update()
      factors[i, "is_factor"] <- FALSE
    }
  }
  factors
}


chars_to_factors <- function(df, factors, levels) {
  description <- ""
  cli_progress_step("Converting{description} to factor")

  for (i in 1:nrow(factors)) {
    factor <- factors[i, ]
    name <- str_to_lower(factor$factor)

    description <- str_c(" ", name)
    cli_progress_update()

    # we need the preprocessed values because we don't want
    # the missingness flags in there
    values <- df[[name]]
    values_as_strings <- as.character(values)
    factor_levels <- levels[levels$column == factor$levels, ]

    values_as_factor <- factor(values_as_strings,
      levels = factor_levels$key,
      labels = factor_levels$value
    )
    df[, name] <- droplevels(values_as_factor)
  }
  df
}


# SPSS data read in using read_sav results in "labeled numbers"
# as opposed to factors; note that labelled has a `to_factor`
# function but we need to do some extra work to get rid of the
# sentinel levels and to detect pseudofactors (factors whose
# only levels are sentinels)

labelled_to_factors <- function(spss_df) {
  name <- ''
  cli_progress_step("Converting to factor: {name}")

  for (name in colnames(spss_df)) {
    labels <- attr(spss_df[[name]], "labels")
    na_range <- attr(spss_df[[name]], "na_range")
    if (is.null(na_range)) {
      na_values <- c()
    } else {
      na_values <- do.call(seq, as.list(na_range))
    }
    label_values <- labels
    # ignore sentinel labels
    true_levels <- setdiff(label_values, na_values)
    true_labels <- names(labels[labels %in% true_levels])
    # values <- remove_val_labels(spss_df[[name]])
    values <- spss_df[[name]]

    if (length(true_labels)) {
      cli_progress_update()
      spss_df[, name] <- factor(values, levels = true_levels, labels = true_labels)
    }
  }
  spss_df
}

# convert spss labeled columns into simple vectors
# (for non-spss data types and for factors, this should be a noop)
unlabel_numbers <- function(spss_df) {
  name <- cli_progress_step("Removing labels from numeric column: {name}")
  for (name in colnames(spss_df)) {
    if (is.labelled(spss_df[[name]]) & (length(levels(spss_df[[name]])) == 0)) {
      cli_progress_update()
      spss_df[, name] <- remove_labels(spss_df[[name]])
    }
  }
  spss_df
}
