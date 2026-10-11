# SiA-WD roundtrip: re-read every mother-table value and compare it with the
# matching cell in the outputs (wide RDS, Shiny filter/info/detailed-RVU RDS,
# OSF RDS and OSF Excel workbook). Read-only apart from two report files.
#
# Usage: Rscript roundtrip.R <repo-root> [YYYYMMDD]
# Subset runs are detected from run_mode_<date>.txt: only those devices are
# compared. Exit status 1 on any mismatch (or a missing output file).
#
# How values are compared:
#   * wide / filter / info: the expected wide row is rebuilt from the mother
#     tables with the documented rules of script 03 (devices columns copied;
#     long tables collapsed per device and key: first non-empty text, maximum
#     for numbers, minimum for sampling_rate_min, mean for scores).
#   * OSF: each overview column is rebuilt from that expected wide row with the
#     documented rules of script 04b (renamed, or derived: 1/0 flags, joined
#     text such as "value; unit", sampling-rate ranges, compatibility text).
#   * detailed RVU: copied cell for cell (Excel sheets sorted by year).
# Columns that cannot be mapped to a mother table are listed, not guessed.

source_dir <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
if (!exists("parse_cli")) source(file.path(source_dir(), "common.R"))

# ---- small building blocks (base R) -----------------------------------------

norm_label <- function(x) {
  x <- gsub("[^a-z0-9]+", "_", tolower(trimws(x)))
  gsub("^_|_$", "", gsub("_+", "_", x))
}

yn_flag <- function(x) {
  x <- tolower(trimws(as.character(x)))
  out <- rep(NA_integer_, length(x))
  out[x %in% c("yes", "y", "true", "t", "1")] <- 1L
  out[x %in% c("no", "n", "false", "f", "0")] <- 0L
  out
}

# Row-wise "a; b; c", dropping empty parts; NA when nothing is left.
paste_parts <- function(...) {
  parts <- lapply(list(...), function(p) {
    p <- as.character(p)
    p[!is.na(p) & p == ""] <- NA_character_
    p
  })
  m <- do.call(cbind, parts)
  if (is.null(m) || nrow(m) == 0) return(character())
  apply(m, 1, function(r) {
    r <- r[!is.na(r)]
    if (length(r)) paste(r, collapse = "; ") else NA_character_
  })
}

# "64", or "26-208" when min and max differ.
rate_text <- function(lo, hi) {
  out <- rep(NA_character_, length(lo))
  only_hi <- is.na(lo) & !is.na(hi)
  only_lo <- !is.na(lo) & is.na(hi)
  both <- !is.na(lo) & !is.na(hi)
  out[only_hi] <- as.character(hi[only_hi])
  out[only_lo] <- as.character(lo[only_lo])
  same <- both & lo == hi
  out[same] <- as.character(lo[same])
  out[both & !same] <- paste0(lo[both & !same], "-", hi[both & !same])
  out
}

col_of <- function(w, name) {
  if (name %in% names(w)) w[[name]] else rep(NA_character_, nrow(w))
}

# ---- expected wide table ----------------------------------------------------

first_value <- function(x) {
  x <- x[!is.na(x)]
  if (length(x)) x[1] else x[NA_integer_]
}

num_stat <- function(fun, int = FALSE) {
  function(x) {
    x <- suppressWarnings(if (int) as.integer(x) else as.numeric(x))
    x <- x[!is.na(x)]
    if (length(x)) fun(x) else NA_real_
  }
}

# Collapse a long table to one value per (device, key) and spread the keys to
# columns named "<key>_<value column>".
collapse_long <- function(ids, key, cols, aggs) {
  ok <- !is.na(ids) & !is.na(key)
  groups <- split(which(ok), paste(ids[ok], key[ok], sep = "\r"))
  if (!length(groups)) return(data.frame(device_id = character()))
  first <- vapply(groups, `[`, integer(1), 1)
  all_dev <- unique(ids[ok])
  out <- list(device_id = all_dev)
  for (cn in names(aggs)) {
    v <- do.call(c, unname(lapply(groups, function(i) aggs[[cn]](cols[[cn]][i]))))
    for (k in unique(key[first])) {
      sel <- key[first] == k
      col <- v[rep(NA_integer_, length(all_dev))]
      col[match(ids[first][sel], all_dev)] <- v[sel]
      out[[paste0(k, "_", cn)]] <- col
    }
  }
  data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
}

SPEC_AGGS <- list(spec_boel_value = first_value,
                  spec_num_value = num_stat(max),
                  spec_num_unit = first_value,
                  spec_char_value = first_value)

build_expected_wide <- function(tabs) {
  dv <- tabs$devices
  ids <- unique(dv$device_id[!is.na(dv$device_id)])
  wide <- dv[match(ids, dv$device_id), , drop = FALSE]
  collapse_spec <- function(d) {
    collapse_long(d$device_id, norm_label(d$spec_name), d, SPEC_AGGS)
  }
  parts <- list(
    collapse_long(
      tabs$scores$device_id,
      paste(norm_label(tabs$scores$score_type),
            norm_label(tabs$scores$score_by), sep = "_"),
      tabs$scores, list(score = num_stat(mean))),
    collapse_spec(tabs$specs),
    collapse_long(
      tabs$signals_long$device_id, norm_label(tabs$signals_long$signal_name),
      tabs$signals_long,
      list(available = first_value,
           sampling_rate_min = num_stat(min),
           sampling_rate_max = num_stat(max),
           additional_info = first_value,
           recording_location = first_value)),
    collapse_spec(tabs$data_access),
    collapse_long(
      tabs$rvu$device_id, norm_label(tabs$rvu$synthesis_type), tabs$rvu,
      list(n_of_studies = num_stat(max, int = TRUE),
           evidence_level = first_value,
           parameters_studied = first_value,
           synthesis = first_value,
           date_of_last_search = first_value))
  )
  for (p in parts) {
    for (cn in setdiff(names(p), "device_id")) {
      wide[[cn]] <- p[[cn]][match(wide$device_id, p$device_id)]
    }
  }
  wide
}

# ---- OSF column mapping -----------------------------------------------------

ren <- function(src) list(kind = "renamed", f = function(w) col_of(w, src))
der <- function(f) list(kind = "derived", f = f)
flag_of <- function(src) der(function(w) yn_flag(col_of(w, src)))
join_of <- function(a, b) {
  der(function(w) paste_parts(col_of(w, a), col_of(w, b)))
}

osf_mapping <- function() {
  signals <- c(PPG = "ppg", ECG = "ecg", ICG = "icg", EMG = "emg",
               Respiration = "respiration", EDA = "eda", EEG = "eeg",
               BP = "bp", Accelerometer = "accelerometer",
               Gyroscope = "gyroscope", GPS = "gps",
               `Skin temperature` = "skin_temperature",
               `Other signals` = "other_signals")
  signal_cell <- function(k) {
    der(function(w) paste_parts(
      yn_flag(col_of(w, paste0(k, "_available"))),
      col_of(w, paste0(k, "_additional_info")),
      rate_text(col_of(w, paste0(k, "_sampling_rate_min")),
                col_of(w, paste0(k, "_sampling_rate_max"))),
      col_of(w, paste0(k, "_recording_location"))))
  }
  os_text <- function(w, label, k) {
    b <- col_of(w, paste0(k, "_compatible_spec_boel_value"))
    ifelse(!is.na(b),
           paste0(label, " ", col_of(w, paste0(k, "_compatible_spec_char_value"))),
           NA_character_)
  }
  storage <- function(w) {
    hr <- paste_parts(col_of(w, "dev_storage_cap_hr_spec_num_value"),
                      col_of(w, "dev_storage_cap_hr_spec_num_unit"))
    mb <- paste_parts(col_of(w, "dev_storage_cap_mb_spec_num_value"),
                      col_of(w, "dev_storage_cap_mb_spec_num_unit"))
    paste_parts(hr, mb)
  }
  last_search <- function(w) {
    a <- col_of(w, "reliability_and_validity_date_of_last_search")
    b <- col_of(w, "usability_date_of_last_search")
    if (all(is.na(a))) return(b)
    i <- is.na(a)
    a[i] <- b[i]
    a
  }
  c(
    list(
      Manufacturer = ren("manufacturer"), Device = ren("model"),
      Website = ren("website"), `Release date` = ren("release_year"),
      `Market status` = ren("market_status"), `Main use` = ren("main_use"),
      `Device costs` = join_of("device_cost", "device_cost_info"),
      `Wearable type` = ren("wearable_type"), Location = ren("location"),
      Weight = ren("weight_gr"), Size = ren("size_mm")),
    lapply(signals, signal_cell),
    list(
      `Water resistance` = flag_of("water_resistance_spec_boel_value"),
      `Battery life` = join_of("battery_life_spec_num_value",
                               "battery_life_spec_num_unit"),
      `Charging method` = ren("charging_method_spec_char_value"),
      `Charging duration` = join_of("charging_duration_spec_num_value",
                                    "charging_duration_spec_num_unit"),
      `Bio-cueing` = flag_of("bio_cueing_spec_boel_value"),
      `Bio-feedback` = flag_of("bio_feedback_spec_boel_value"),
      `Raw data available` = flag_of("raw_data_available_spec_boel_value"),
      `Provided parameters` = ren("parameters_available_spec_char_value"),
      `Parameter sampling window (1min; 5min; 1hour; 1day)` =
        ren("parameters_resolution_spec_char_value"),
      `Data transfer method` = ren("data_transfer_method_spec_char_value"),
      Compatibility = der(function(w) paste_parts(
        os_text(w, "Windows", "windows"), os_text(w, "iOS", "ios"),
        os_text(w, "Android", "android"), os_text(w, "macOS", "macos"))),
      `Required software` = ren("software_required_spec_char_value"),
      `Additional software` = ren("software_additional_spec_char_value"),
      `Internal storage method` = ren("int_storage_met_spec_char_value"),
      `Device storage capacity` = der(storage),
      `Server Data Storage` = ren("server_data_storage_spec_char_value"),
      `GDPR compliance` = flag_of("gdpr_compliance_spec_boel_value"),
      `FDA approval/clearance` = flag_of("fda_clearance_spec_boel_value"),
      `CE approval/label` = flag_of("ce_marking_spec_boel_value"),
      `Highest level of Validation Evidence` =
        ren("reliability_and_validity_evidence_level"),
      `Number of validity and reliability studies reviewed` =
        ren("reliability_and_validity_n_of_studies"),
      `Studied parameters` = ren("reliability_and_validity_parameters_studied"),
      `General validity and reliability synthesis` =
        ren("reliability_and_validity_synthesis"),
      `Number of usability studies reviewed` = ren("usability_n_of_studies"),
      `General usability synthesis` = ren("usability_synthesis"),
      `Hyperlink to the device VRU page` =
        der(function(w) rep(NA_character_, nrow(w))),  # empty by design
      `Most recent date of RVU search` = der(last_search),
      `SiA Expert score (short-term)` = ren("short_term_all_score"),
      `SiA Expert score (long-term)` = ren("long_term_all_score")
    )
  )
}

build_expected_osf <- function(wide, mapping = osf_mapping()) {
  vals <- lapply(mapping, function(m) m$f(wide))
  data.frame(c(list(device_id = wide$device_id), vals),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# ---- comparison engine ------------------------------------------------------

mismatch <- function(table, device_id, column, expected, found) {
  n <- length(device_id)
  data.frame(table = rep(table, length.out = n), device_id = device_id,
             column = rep(column, length.out = n),
             expected = rep(show_value(expected), length.out = n),
             found = rep(show_value(found), length.out = n),
             stringsAsFactors = FALSE)
}

bind_mm <- function(x) {
  x <- Filter(function(d) !is.null(d) && nrow(d) > 0, x)
  if (!length(x)) return(mismatch(character(), character(), character(),
                                  character(), character()))
  do.call(rbind, x)
}

# Cells matched by device_id.
compare_by_device <- function(expected, found, table, cols) {
  pos <- match(expected$device_id, found$device_id)
  have <- !is.na(pos)
  mm <- list()
  n_cells <- 0L
  for (cn in cols) {
    ok <- same_value(expected[[cn]][have], found[[cn]][pos[have]])
    n_cells <- n_cells + length(ok)
    i <- which(have)[!ok]
    mm[[length(mm) + 1]] <- mismatch(table, expected$device_id[i], cn,
                                     expected[[cn]][i], found[[cn]][pos[i]])
  }
  list(mismatches = bind_mm(mm), n_cells = n_cells)
}

# Cells matched by study (device_id + citation), so one lost row does not
# shift every row after it. Used for the detailed RVU tables.
compare_by_study <- function(expected, found, table, cols) {
  e <- add_key(expected, TRUE)
  f <- add_key(found, TRUE)
  pos <- match(e$.key, f$.key)
  have <- !is.na(pos)
  cite <- function(d) if ("study_citation" %in% names(d)) substr(d$study_citation, 1, 60) else d$.key
  extra <- setdiff(f$.key, e$.key)
  mm <- list(
    mismatch(table, e$device_id[!have], "<study>", cite(e)[!have], "missing from output"),
    mismatch(table, f$device_id[f$.key %in% extra], "<study>", "not in source",
             cite(f)[f$.key %in% extra]))
  n_cells <- 0L
  for (cn in cols) {
    ok <- same_value(e[[cn]][have], f[[cn]][pos[have]])
    n_cells <- n_cells + length(ok)
    i <- which(have)[!ok]
    mm[[length(mm) + 1]] <- mismatch(table, e$device_id[i], cn,
                                     e[[cn]][i], f[[cn]][pos[i]])
  }
  list(mismatches = bind_mm(mm), n_cells = n_cells)
}

# Devices missing, extra or duplicated in an output.
compare_devices <- function(expected_ids, found_ids, table) {
  gone <- setdiff(expected_ids, found_ids)
  extra <- setdiff(found_ids, expected_ids)
  dups <- unique(found_ids[duplicated(found_ids)])
  bind_mm(list(
    mismatch(table, gone, "<device>", "present", "missing from output"),
    mismatch(table, extra, "<device>", "not in devices.xlsx", "present in output"),
    mismatch(table, dups, "<device>", "one row", "several rows")))
}

# Expected columns that the output does not carry at all.
missing_columns <- function(expected_cols, found_cols, table) {
  gone <- setdiff(expected_cols, found_cols)
  mismatch(table, rep(NA_character_, length(gone)), gone,
           "<column>", "column missing")
}

check_frame <- function(expected, found, table, cols = NULL) {
  cols <- if (is.null(cols)) setdiff(names(expected), "device_id") else cols
  cols <- intersect(cols, names(found))
  res <- compare_by_device(expected, found, table, cols)
  res$mismatches <- bind_mm(list(
    compare_devices(expected$device_id, found$device_id, table),
    res$mismatches))
  res$skipped <- setdiff(names(found), c(names(expected), "device_id"))
  res
}

# ---- run ---------------------------------------------------------------------

load_output <- function(path) {
  if (!file.exists(path)) return(NULL)
  as.data.frame(readRDS(path), stringsAsFactors = FALSE)
}

missing_file <- function(table, path) {
  list(mismatches = mismatch(table, NA_character_, "<file>", "file exists",
                             paste("missing:", basename(path))),
       n_cells = 0L, skipped = character())
}

roundtrip_all <- function(tabs, files) {
  exp_wide <- build_expected_wide(tabs)
  res <- list()
  wide <- load_output(files[["wide"]])
  filt <- load_output(files[["filter"]])
  info <- load_output(files[["info"]])

  res[["wide RDS"]] <- if (is.null(wide)) missing_file("wide RDS", files[["wide"]])
    else {
      r <- check_frame(exp_wide, wide, "wide RDS")
      r$mismatches <- bind_mm(list(
        r$mismatches, missing_columns(names(exp_wide), names(wide), "wide RDS")))
      r
    }
  for (nm in c("filter", "info")) {
    lab <- paste("Shiny", nm, "RDS")
    d <- list(filter = filt, info = info)[[nm]]
    res[[lab]] <- if (is.null(d)) missing_file(lab, files[[nm]])
      else check_frame(exp_wide, d, lab)
  }
  if (!is.null(filt) && !is.null(info)) {
    res[["Shiny filter RDS"]]$mismatches <- bind_mm(list(
      res[["Shiny filter RDS"]]$mismatches,
      missing_columns(names(exp_wide), c(names(filt), names(info)),
                      "Shiny filter+info RDS")))
  }

  exp_osf <- build_expected_osf(exp_wide)
  osf <- load_output(files[["osf_rds"]])
  res[["OSF RDS"]] <- if (is.null(osf)) missing_file("OSF RDS", files[["osf_rds"]])
    else {
      r <- check_frame(exp_osf, osf, "OSF RDS")
      r$mismatches <- bind_mm(list(
        r$mismatches, missing_columns(names(exp_osf), names(osf), "OSF RDS")))
      r
    }

  det <- load_output(files[["rvu"]])
  rv <- tabs$rvu_detailed
  res[["Shiny detailed RVU RDS"]] <- if (is.null(det)) {
    missing_file("Shiny detailed RVU RDS", files[["rvu"]])
  } else {
    r <- compare_by_study(rv, det, "Shiny detailed RVU RDS", intersect(names(rv), names(det)))
    r$mismatches <- bind_mm(list(
      r$mismatches,
      missing_columns(names(rv), names(det), "Shiny detailed RVU RDS")))
    r$skipped <- setdiff(names(det), names(rv))
    r
  }

  res[["OSF workbook"]] <- check_workbook(files[["osf_xls"]], exp_osf)
  res[["OSF workbook device sheets"]] <- check_sheets(files[["osf_xls"]], rv)
  res
}

check_workbook <- function(path, exp_osf) {
  if (!file.exists(path)) return(missing_file("OSF workbook", path))
  x <- as.data.frame(readxl::read_xlsx(path, sheet = 1))
  r <- check_frame(exp_osf, x, "OSF workbook")
  r$mismatches <- bind_mm(list(
    r$mismatches, missing_columns(names(exp_osf), names(x), "OSF workbook")))
  r
}

check_sheets <- function(path, rv) {
  tab <- "OSF workbook device sheets"
  if (!file.exists(path)) return(missing_file(tab, path))
  sheets <- readxl::excel_sheets(path)
  mm <- list()
  n_cells <- 0L
  for (d in unique(rv$device_id)) {
    sh <- substr(d, 1, 31)
    if (!sh %in% sheets) {
      mm[[length(mm) + 1]] <- mismatch(tab, d, "<sheet>", "sheet exists", "sheet missing")
      next
    }
    e <- rv[rv$device_id == d, , drop = FALSE]
    e <- e[order(e$year, na.last = TRUE), , drop = FALSE]
    f <- as.data.frame(readxl::read_xlsx(path, sheet = sh))
    r <- compare_by_study(e, f, tab, intersect(names(e), names(f)))
    n_cells <- n_cells + r$n_cells
    mm[[length(mm) + 1]] <- r$mismatches
    mm[[length(mm) + 1]] <- missing_columns(names(e), names(f), tab)
  }
  extra <- setdiff(sheets, c("df_osf_sia_wd", substr(unique(rv$device_id), 1, 31)))
  if (length(extra)) {
    mm[[length(mm) + 1]] <- mismatch(tab, rep(NA_character_, length(extra)),
                                     extra, "no such sheet", "sheet present")
  }
  list(mismatches = bind_mm(mm), n_cells = n_cells, skipped = character())
}

# ---- report -----------------------------------------------------------------

summarise_results <- function(res) {
  do.call(rbind, lapply(names(res), function(nm) {
    mm <- res[[nm]]$mismatches
    data.frame(output = nm, cells_checked = res[[nm]]$n_cells,
               mismatches = nrow(mm),
               devices_affected = length(unique(stats::na.omit(mm$device_id))),
               stringsAsFactors = FALSE)
  }))
}

report_lines <- function(res, mode, n_devices, ds, detail_max = 15) {
  s <- summarise_results(res)
  m <- mapping_kinds()
  L <- c(sprintf("SiA-WD roundtrip check, run date %s, %d devices compared",
                 ds, n_devices))
  if (is_partial(mode)) L <- c(L, PARTIAL_NOTE)
  L <- c(L, "", "Output | cells checked | mismatches | devices affected")
  L <- c(L, sprintf("%s | %d | %d | %d", s$output, s$cells_checked,
                    s$mismatches, s$devices_affected))
  for (nm in names(res)) {
    mm <- res[[nm]]$mismatches
    if (!nrow(mm)) next
    L <- c(L, "", sprintf("Mismatches in %s (%d):", nm, nrow(mm)))
    top <- utils::head(mm, detail_max)
    L <- c(L, sprintf("  device %s | column %s | expected %s | found %s",
                      top$device_id, top$column, top$expected, top$found))
    if (nrow(mm) > detail_max)
      L <- c(L, sprintf("  ... %d more, see the CSV", nrow(mm) - detail_max))
  }
  L <- c(L, "", "How derived columns were checked:",
         sprintf("  OSF renamed columns (%d): copied from the wide value", length(m$renamed)),
         sprintf("  OSF derived columns (%d): rebuilt with the documented rule: %s",
                 length(m$derived), paste(m$derived, collapse = ", ")),
         "  Wide columns: rebuilt from the long mother tables (first non-empty text, max for numbers, min for sampling_rate_min, mean for scores)")
  for (nm in names(res)) {
    sk <- res[[nm]]$skipped
    if (length(sk))
      L <- c(L, sprintf("Skipped in %s (cannot map to a mother table, not compared): %s",
                        nm, paste(sk, collapse = ", ")))
  }
  total <- sum(s$mismatches)
  c(L, "", if (total) sprintf("RESULT: %d mismatch(es). Do not publish until explained.", total)
    else "RESULT: every mapped cell matches its mother-table source.")
}

mapping_kinds <- function() {
  m <- osf_mapping()
  kind <- vapply(m, `[[`, "", "kind")
  list(renamed = names(m)[kind == "renamed"], derived = names(m)[kind == "derived"])
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  cli <- parse_cli(args)
  proc <- file.path(cli$root, "data", "processed")
  mode <- read_run_mode(proc, cli$ds)
  tabs <- read_mother_tables(cli$root)
  if (is_partial(mode)) tabs <- apply_device_filter(tabs, mode$devices)
  res <- roundtrip_all(tabs, output_paths(proc, cli$ds))
  lines <- report_lines(res, mode, length(unique(tabs$devices$device_id)), cli$ds)
  writeLines(lines)
  vdir <- file.path(proc, "verification")
  dir.create(vdir, showWarnings = FALSE)
  sfx <- report_suffix(mode)
  writeLines(lines, file.path(vdir, paste0("roundtrip_summary_", cli$ds, sfx, ".txt")))
  all_mm <- bind_mm(lapply(res, `[[`, "mismatches"))
  utils::write.csv(all_mm, file.path(vdir, paste0("roundtrip_mismatches_", cli$ds, sfx, ".csv")),
                   row.names = FALSE, na = "", fileEncoding = "UTF-8")
  quit(status = if (nrow(all_mm)) 1L else 0L)
}

if (sys.nframe() == 0L) main()
