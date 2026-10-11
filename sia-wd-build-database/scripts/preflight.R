# SiA-WD preflight: read-only checks of R, packages and the 7 mother tables.
# Usage: Rscript preflight.R <path-to-repo-root>
# Writes nothing. Exit status 1 if any FAIL, else 0.
# Expectations are derived from the repo scripts in src/application/.

# Optional subset check: add --devices=id1,id2 or --devices-file=path.
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])))
source(file.path(script_dir, "common.R"))
cli <- parse_cli(commandArgs(trailingOnly = TRUE))
root <- cli$root

res <- list()
add <- function(level, msg) {
  res[[length(res) + 1]] <<- c(level, msg)
  cat(sprintf("[%s] %s\n", level, msg))
}

# ---- 1 repo layout ----
needed_scripts <- c(
  "src/application/01.sia.p1.packages.R",
  "src/application/02.sia.p1.read.data.R",
  "src/application/03.sia.p1.wd.data.wide.R",
  "src/application/04a.sia.p1.wd.data.wide.to.shiny.R",
  "src/application/04b.sia.p1.wd.data.wide.to.osf.R",
  "src/function/sai.p1.functions.R"
)
miss <- needed_scripts[!file.exists(file.path(root, needed_scripts))]
# The UI step has two possible names (see UI_SCRIPTS in common.R).
if (is.na(ui_script(root))) {
  miss <- c(miss, paste(UI_SCRIPTS, collapse = " or "))
} else {
  add("INFO", paste("UI step:", ui_script(root)))
}
if (length(miss)) {
  add("FAIL", paste("Repo scripts missing:", paste(miss, collapse = ", ")))
} else {
  add("PASS", "All pipeline scripts found.")
}
if (!dir.exists(file.path(root, "data", "raw"))) add("FAIL", "Folder data/raw not found.")
if (!dir.exists(file.path(root, "data", "processed"))) add("FAIL", "Folder data/processed not found (outputs are written there).")

# ---- 2 R and packages ----
add("INFO", paste("R version:", paste(R.version$major, R.version$minor, sep = ".")))
pkgs <- c("here", "readxl", "dplyr", "tidyr", "janitor", "writexl",
          "readr", "purrr", "rvest", "shiny")
pkg_missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(pkg_missing)) {
  add("FAIL", paste("Missing R packages:", paste(pkg_missing, collapse = ", ")))
  cat("INSTALL: install.packages(c(",
      paste0('"', pkg_missing, '"', collapse = ", "), "))\n", sep = "")
} else add("PASS", "All required R packages installed.")

if (any(vapply(res, function(r) r[1] == "FAIL", logical(1)))) {
  cat("\nStopping table checks: fix the items above first.\n")
  quit(status = 1)
}

suppressPackageStartupMessages({
  library(dplyr); library(readxl); library(janitor)
})
source(file.path(root, "src", "function", "sai.p1.functions.R"))  # norm_key()

# ---- 3 mother tables ----
na_vals <- c("", "NA", "NP", "N/A", "Na", "na", "NULL", "-9999")  # same as 02 script

spec <- list(
  devices = list(file = "devices.xlsx",
    cols = c("device_id", "manufacturer", "model", "website", "release_year",
             "market_status", "main_use", "device_cost", "device_cost_info",
             "wearable_type", "location", "size_mm", "weight_gr")),
  signals = list(file = "signals.xlsx",
    cols = c("device_id", "signal_name", "available", "sampling_rate_min",
             "sampling_rate_max", "additional_info", "recording_location"),
    key = "signal_name",
    keys = c("ppg", "ecg", "icg", "emg", "respiration", "eda", "eeg", "bp",
             "accelerometer", "gyroscope", "gps", "skin_temperature", "other_signals"),
    num = c("sampling_rate_min", "sampling_rate_max")),
  technical_specs = list(file = "technical_specs.xlsx",
    cols = c("device_id", "spec_name", "spec_boel_value", "spec_num_value",
             "spec_num_unit", "spec_char_value"),
    key = "spec_name",
    keys = c("water_resistance", "battery_life", "charging_method",
             "charging_duration", "bio_cueing", "bio_feedback"),
    num = "spec_num_value"),
  data_access = list(file = "data_access.xlsx",
    cols = c("device_id", "spec_name", "spec_boel_value", "spec_num_value",
             "spec_num_unit", "spec_char_value"),
    key = "spec_name",
    keys = c("raw_data_available", "parameters_available", "parameters_resolution",
             "data_transfer_method", "windows_compatible", "macos_compatible",
             "android_compatible", "ios_compatible", "software_required",
             "software_additional", "int_storage_met", "server_data_storage",
             "dev_storage_cap_hr", "dev_storage_cap_mb", "gdpr_compliance",
             "fda_clearance", "ce_marking"),
    num = "spec_num_value"),
  rvu_synthesis = list(file = "rvu_synthesis.xlsx",
    cols = c("device_id", "synthesis_type", "n_of_studies", "evidence_level",
             "parameters_studied", "synthesis", "date_of_last_search"),
    key = "synthesis_type",
    keys = c("reliability_and_validity", "usability"),
    num = "n_of_studies"),
  expert_scores = list(file = "expert_scores.xlsx",
    cols = c("device_id", "score_type", "score_by", "score"),
    key = "score_type",
    keys = c("short_term", "long_term"),
    by = "score_by",  # one row per reviewer (rev1, rev2, ..., all); script 03 keeps each apart
    num = "score"),
  rvu_synthesis_detailed = list(file = "rvu_synthesis_detailed.xlsx",
    cols = c("device_id", "year"))
)

tabs <- list()
for (nm in names(spec)) {
  s <- spec[[nm]]
  p <- file.path(root, "data", "raw", s$file)
  if (!file.exists(p)) { add("FAIL", paste0(s$file, " not found in data/raw (exact name needed).")); next }
  d <- tryCatch(read_xlsx(p, na = na_vals) %>% clean_names(),
                error = function(e) { add("FAIL", paste0(s$file, " cannot be read: ", conditionMessage(e))); NULL })
  if (is.null(d)) next
  mc <- setdiff(s$cols, names(d))
  if (length(mc)) { add("FAIL", paste0(s$file, ": missing columns ", paste(mc, collapse = ", "))); next }
  if (nrow(d) == 0) { add("FAIL", paste0(s$file, " has no rows.")); next }
  tabs[[nm]] <- d
  add("PASS", sprintf("%s: %d rows, %d devices, columns OK.", s$file, nrow(d), n_distinct(d$device_id)))
  if (anyNA(d$device_id)) add("FAIL", paste0(s$file, ": empty device_id cells."))

  if (!is.null(s$key)) {
    present <- unique(norm_key(as.character(d[[s$key]])))
    absent <- setdiff(s$keys, present)
    extra <- setdiff(present, c(s$keys, NA))
    if (length(absent)) add("FAIL", paste0(s$file, ": expected ", s$key, " values missing: ", paste(absent, collapse = ", "),
                                           " (the OSF/Shiny scripts refer to these by name)."))
    if (length(extra)) add("WARN", paste0(s$file, ": ", s$key, " values not used by the OSF/Shiny scripts (they only enter the wide table): ",
                                          paste(extra, collapse = ", ")))
    d_k <- d %>% mutate(.k = norm_key(as.character(.data[[s$key]])))
    if (!is.null(s$by)) d_k <- d_k %>% mutate(.b = norm_key(as.character(.data[[s$by]])))
    dup <- d_k %>% count(across(any_of(c("device_id", ".k", ".b")))) %>% filter(n > 1)
    what <- if (is.null(s$by)) paste0("device/", s$key) else paste0("device/", s$key, "/", s$by)
    if (nrow(dup)) add("WARN", sprintf("%s: %d %s combinations appear more than once (e.g. %s); the pipeline silently merges them (first value or max/mean).",
                                       s$file, nrow(dup), what, dup$device_id[1]))
  }
  for (cn in s$num) {
    v <- d[[cn]]
    bad <- sum(!is.na(v) & is.na(suppressWarnings(as.numeric(v))))
    if (bad) add("WARN", sprintf("%s: %d non-numeric entries in %s will become empty.", s$file, bad, cn))
  }
}

# ---- 4 keys across tables ----
if ("devices" %in% names(tabs)) {
  dv <- tabs$devices
  if (anyDuplicated(dv$device_id)) add("FAIL", "devices.xlsx: device_id must be unique (one row per device).")
  ids <- dv$device_id
  for (nm in setdiff(names(tabs), "devices")) {
    orphan <- setdiff(tabs[[nm]]$device_id, ids)
    if (length(orphan)) add(if (nm == "expert_scores") "FAIL" else "WARN",
      sprintf("%s: %d device_id not in devices.xlsx (e.g. %s).", nm, length(orphan), paste(head(orphan, 3), collapse = ", ")))
    none <- setdiff(ids, tabs[[nm]]$device_id)
    if (length(none) && nm == "expert_scores") {
      # A device without expert scores is fine, but it needs placeholder rows
      # (score -9999 for every score_type x score_by): script 03 builds the wide
      # table from expert_scores, so a device with no rows at all is dropped.
      es <- tabs$expert_scores
      unscored <- unique(es$device_id)[tapply(is.na(suppressWarnings(as.numeric(es$score))), es$device_id, all)[unique(es$device_id)]]
      add("FAIL", sprintf(
        "%d device(s) have no rows in expert_scores.xlsx: %s. Devices without expert scores need placeholder rows with score -9999 (one per score_type and score_by, as %s have), otherwise the device is DROPPED from the database and the app.",
        length(none), paste(none, collapse = ", "),
        if (length(unscored)) paste(head(unscored, 4), collapse = ", ") else "other unscored devices"))
    } else if (length(none) && nm != "rvu_synthesis_detailed") {
      add("WARN", sprintf("%d devices have no rows in %s (e.g. %s); their columns stay empty.",
                          length(none), nm, paste(head(none, 3), collapse = ", ")))
    }
  }
  if ("expert_scores" %in% names(tabs)) {
    rv <- unique(norm_key(as.character(tabs$expert_scores$score_by)))
    if (!"all" %in% rv) add("FAIL", "expert_scores.xlsx: no score_by = 'all' rows (needed for short_term_all_score / long_term_all_score).")
  }
}
if ("rvu_synthesis_detailed" %in% names(tabs)) {
  sh <- unique(substr(tabs$rvu_synthesis_detailed$device_id, 1, 31))
  if (length(sh) < n_distinct(tabs$rvu_synthesis_detailed$device_id))
    add("FAIL", "rvu_synthesis_detailed.xlsx: device_ids are not unique within the first 31 characters (Excel sheet names).")
}

# ---- 5 requested subset (only with --devices / --devices-file) ----
if (!is.null(cli$devices)) {
  add("INFO", sprintf("PARTIAL RUN requested: %d device(s). Outputs will be marked not for publication.", length(cli$devices)))
  gone <- missing_devices(tabs, cli$devices)
  all_ids <- unique(unlist(lapply(tabs, `[[`, "device_id")))
  for (id in unique(gone$device_id)) {
    where <- gone$table[gone$device_id == id]
    hint <- agrep(id, all_ids, value = TRUE, max.distance = 0.2)
    level <- if (any(where %in% c("devices", "expert_scores"))) "FAIL" else "WARN"
    add(level, sprintf("Requested device_id '%s' not found in: %s.%s", id, paste(where, collapse = ", "),
                       if (length(hint)) paste0(" Did you mean: ", paste(head(hint, 3), collapse = ", "), "?") else ""))
  }
  if (!nrow(gone)) add("PASS", "Every requested device_id exists in all mother tables.")
}

# ---- 6 summary ----
lv <- vapply(res, `[`, "", 1)
cat(sprintf("\nSummary: %d PASS, %d WARN, %d FAIL\n", sum(lv == "PASS"), sum(lv == "WARN"), sum(lv == "FAIL")))
quit(status = if (any(lv == "FAIL")) 1 else 0)
