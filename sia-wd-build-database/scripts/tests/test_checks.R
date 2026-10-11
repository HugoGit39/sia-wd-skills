# Tests for the verification helpers, with tiny synthetic fixtures.
# Run: Rscript -e 'testthat::test_file("scripts/tests/test_checks.R")'
# Needs only testthat (no readxl/janitor): the helpers are base R.

library(testthat)
source("../common.R")
source("../roundtrip.R")
source("../release_diff.R")

fixture_tabs <- function() {
  list(
    devices = data.frame(device_id = c("a", "b"), manufacturer = c("X", "Y"),
                         model = c("m1", "m2"), stringsAsFactors = FALSE),
    scores = data.frame(device_id = c("a", "a", "a", "b"),
                        score_type = c("Short-term", "Short-term", "short term", "Long-term"),
                        score_by = c("all", "all", "rev1", "all"),
                        score = c(4, 6, 7, 9), stringsAsFactors = FALSE),
    specs = data.frame(device_id = c("a", "a"), spec_name = "Battery life",
                       spec_boel_value = c(NA, "yes"),
                       spec_num_value = c("10", "24"),
                       spec_num_unit = c(NA, "hr"),
                       spec_char_value = NA_character_, stringsAsFactors = FALSE),
    signals_long = data.frame(device_id = c("a", "a"), signal_name = "PPG",
                              available = c("no", "yes"),
                              sampling_rate_min = c(64, 25),
                              sampling_rate_max = c(64, 128),
                              additional_info = c(NA, "green"),
                              recording_location = "wrist",
                              stringsAsFactors = FALSE),
    data_access = data.frame(device_id = "b", spec_name = "Windows compatible",
                             spec_boel_value = "yes", spec_num_value = NA_real_,
                             spec_num_unit = NA_character_,
                             spec_char_value = NA_character_,
                             stringsAsFactors = FALSE),
    rvu = data.frame(device_id = "a", synthesis_type = "Usability",
                     n_of_studies = c("3.7"), evidence_level = "low",
                     parameters_studied = NA, synthesis = "ok",
                     date_of_last_search = NA, stringsAsFactors = FALSE),
    rvu_detailed = data.frame(device_id = c("a", "a", "b"),
                              study_citation = c("s2", "s1", "s3"),
                              year = c(2022, 2020, 2021), stringsAsFactors = FALSE)
  )
}

test_that("same_value treats both-empty as equal and uses numeric tolerance", {
  expect_equal(same_value(c(NA, 1, 2, NaN), c(NA, 1 + 1e-12, 3, NA)),
               c(TRUE, TRUE, FALSE, TRUE))
  expect_false(same_value("a", NA))
  expect_true(same_value(1, "1"))
  t1 <- as.POSIXct("2020-01-01", tz = "UTC")
  expect_true(same_value(t1, t1))
})

test_that("read_device_ids merges list and file, drops comments", {
  f <- tempfile()
  writeLines(c("# my selection", "c", "d  # inline"), f)
  expect_equal(read_device_ids("a, b", f), c("a", "b", "c", "d"))
  expect_null(read_device_ids())
  expect_error(read_device_ids(" , "), "empty")
})

test_that("device filter covers rvu_detailed and reports missing ids", {
  tabs <- fixture_tabs()
  sub <- apply_device_filter(tabs, "a")
  expect_equal(unique(sub$rvu_detailed$device_id), "a")
  expect_true(all(vapply(sub, function(d) all(d$device_id == "a"), logical(1))))
  gone <- missing_devices(tabs, c("a", "zzz"))
  expect_equal(sum(gone$device_id == "zzz"), length(tabs))
  expect_equal(gone$table[gone$device_id == "a"], "data_access")
  b <- missing_devices(tabs, "b")
  expect_setequal(b$table, c("specs", "signals_long", "rvu"))
})

test_that("expected wide applies the documented collapse rules", {
  w <- build_expected_wide(fixture_tabs())
  a <- w[w$device_id == "a", ]
  expect_equal(a$short_term_all_score, 5)            # mean of 4 and 6
  expect_equal(a$short_term_rev1_score, 7)           # label "short term" normalised
  expect_equal(a$battery_life_spec_num_value, 24)    # max
  expect_equal(a$battery_life_spec_boel_value, "yes") # first non-empty
  expect_equal(a$ppg_sampling_rate_min, 25)          # min
  expect_equal(a$ppg_sampling_rate_max, 128)
  expect_equal(a$ppg_available, "no")                # first non-empty
  expect_equal(a$usability_n_of_studies, 3)          # integer truncation
  expect_true(is.na(w$short_term_all_score[w$device_id == "b"]))
})

test_that("OSF mapping rebuilds derived cells", {
  w <- build_expected_wide(fixture_tabs())
  osf <- build_expected_osf(w)
  expect_equal(osf$PPG[1], "0; green; 25-128; wrist")
  expect_equal(osf$`Battery life`[1], "24; hr")
  expect_equal(osf$Compatibility[2], "Windows NA")   # quirk of script 04b
  expect_true(is.na(osf$`Hyperlink to the device VRU page`[1]))
  expect_equal(rate_text(c(5, NA, 3), c(5, 9, NA)), c("5", "9", "3"))
  expect_equal(yn_flag(c("Yes", "n", "maybe")), c(1L, 0L, NA))
  kinds <- mapping_kinds()
  expect_true("PPG" %in% kinds$derived && "Manufacturer" %in% kinds$renamed)
})

test_that("check_frame finds a changed cell, a missing device and skips unmapped columns", {
  exp <- data.frame(device_id = c("a", "b"), x = c(1, 2), y = c("p", "q"),
                    stringsAsFactors = FALSE)
  ok <- check_frame(exp, exp, "t")
  expect_equal(nrow(ok$mismatches), 0)
  expect_equal(ok$n_cells, 4)
  bad <- data.frame(device_id = "a", x = 1.5, y = "p", extra = 1,
                    stringsAsFactors = FALSE)
  r <- check_frame(exp, bad, "t")
  expect_setequal(r$mismatches$column, c("x", "<device>"))
  expect_equal(r$skipped, "extra")
  miss <- missing_columns(c("x", "z"), "x", "t")
  expect_equal(miss$column, "z")
})

test_that("compare_by_study matches by citation, so a lost row does not shift others", {
  e <- data.frame(device_id = "a", study_citation = c("s1", "s2", "s3"),
                  year = c(2020, 2021, 2022), stringsAsFactors = FALSE)
  f <- data.frame(device_id = "a", study_citation = c("s2", "s3", "s9"),
                  year = c(2021, 2099, 5), stringsAsFactors = FALSE)
  r <- compare_by_study(e, f, "t", "year")
  expect_equal(sort(r$mismatches$column), c("<study>", "<study>", "year"))
  expect_equal(r$n_cells, 2)
})

write_set <- function(dir, ds, wide, filter = wide, mode_devices = "none") {
  saveRDS(wide, file.path(dir, paste0("df_wide_sia_wd_", ds, ".rds")))
  saveRDS(filter, file.path(dir, paste0("df_shiny_sia_wd_filter_", ds, ".rds")))
  if (!identical(mode_devices, "none")) write_run_mode(dir, ds, mode_devices)
}

test_that("previous release skips later dates and partial runs", {
  dir <- tempfile(); dir.create(dir)
  w <- data.frame(device_id = "a")
  write_set(dir, "20260101", w)
  write_set(dir, "20260201", w, mode_devices = "a")  # partial: never a baseline
  write_set(dir, "20260301", w)
  write_set(dir, "20260401", w)
  expect_equal(find_previous_release(dir, "20260301")$date, "20260101")
  expect_equal(find_previous_release(dir, "20260401")$date, "20260301")
  expect_null(find_previous_release(dir, "20260101"))
  expect_equal(find_previous_release(dir, "20260401", "20260101")$date, "20260101")
  expect_null(find_previous_release(dir, "20260401", "20250101"))
})

test_that("release diff reports changes, adds and removals, and subset ignores others", {
  old <- data.frame(device_id = c("a", "b", "c"), manufacturer = "X",
                    model = c("m1", "m2", "m3"), score = c(5, 6, 7),
                    stringsAsFactors = FALSE)
  new <- data.frame(device_id = c("a", "b", "d"), manufacturer = "X",
                    model = c("m1", "m2", "m4"), score = c(5, 8, 7),
                    stringsAsFactors = FALSE)
  d1 <- tempfile(); d2 <- tempfile(); dir.create(d1); dir.create(d2)
  write_set(d1, "20260101", old); write_set(d2, "20260201", new)
  full <- compare_releases(output_paths(d1, "20260101"), output_paths(d2, "20260201"))
  expect_equal(full$added, "d")
  expect_equal(full$removed, "c")
  ch <- full$changes[full$changes$change == "changed", ]
  expect_equal(unique(ch$device_id), "b")
  expect_equal(c(ch$old[ch$field == "score"], ch$new[ch$field == "score"]), c("6", "8"))

  sub <- compare_releases(output_paths(d1, "20260101"), output_paths(d2, "20260201"), "b")
  expect_length(sub$removed, 0)   # c is outside the subset: never "removed"
  expect_length(sub$added, 0)
  txt <- format_report(sub, "20260201", "20260101",
                       list(mode = "PARTIAL", devices = "b"), "b")
  expect_true(any(grepl("PARTIAL RUN", txt)))
  expect_true(any(grepl("b \\| score \\| 6 -> 8", txt)))
})

test_that("run mode roundtrip and plausibility facts", {
  dir <- tempfile(); dir.create(dir)
  expect_equal(read_run_mode(dir, "20260101")$mode, "FULL")
  write_run_mode(dir, "20260101", c("a", "b"))
  m <- read_run_mode(dir, "20260101")
  expect_equal(m$devices, c("a", "b"))
  write_run_mode(dir, "20260101")
  expect_null(read_run_mode(dir, "20260101")$devices)
  filt <- data.frame(device_id = c("a", "b"), short_term_all_score = c(4, 11),
                     release_year = c(2020, 2999), battery = c(NA, NA))
  facts <- paste(profile_facts(filt, 2026), collapse = "\n")
  expect_match(facts, "SCORE OUTSIDE 0-10 in short_term_all_score: b")
  expect_match(facts, "release_year in the future")
})
