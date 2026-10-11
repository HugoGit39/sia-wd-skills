# SiA-WD validate: read-only checks on the files a run produced.
# Usage: Rscript validate.R <path-to-repo-root> [YYYYMMDD]   (default: today)
# A subset run is detected from run_mode_<date>.txt and labelled PARTIAL.
# Exit status 1 if any FAIL.

suppressPackageStartupMessages({ library(readxl); library(dplyr) })
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])))
source(file.path(script_dir, "common.R"))
cli <- parse_cli(commandArgs(trailingOnly = TRUE))
root <- normalizePath(cli$root, mustWork = TRUE)
ds <- cli$ds
proc <- file.path(root, "data", "processed")
na_vals <- NA_TOKENS
mode <- read_run_mode(proc, ds)  # a subset run is recorded by run_pipeline.R
if (is_partial(mode)) cat("*** ", PARTIAL_NOTE, " (", length(mode$devices), " devices)\n\n", sep = "")

fails <- 0L
chk <- function(ok, pass, fail, level = "FAIL") {
  if (isTRUE(ok)) cat("[PASS]", pass, "\n")
  else { cat(sprintf("[%s] %s\n", level, fail)); if (level == "FAIL") fails <<- fails + 1L }
  invisible(ok)
}

# ---- expected files ----
f <- c(
  wide    = paste0("df_wide_sia_wd_", ds, ".rds"),
  filter  = paste0("df_shiny_sia_wd_filter_", ds, ".rds"),
  info    = paste0("df_shiny_sia_wd_info_", ds, ".rds"),
  rvu     = paste0("df_shiny_rvu_detailed", ds, ".rds"),   # no underscore before the date: as written in 04a
  osf_rds = paste0("df_osf_sia_wd_shiny_", ds, ".rds"),
  osf_xls = paste0("df_osf_sia_wd_", ds, ".xlsx")
)
ui <- c(paste0("ui_constants_", ds, ".rds"), paste0("glos_", ds, ".rds"), paste0("updates_", ds, ".rds"))
for (n in names(f)) chk(file.exists(file.path(proc, f[[n]])), paste(f[[n]], "exists."), paste(f[[n]], "is missing."))
for (u in ui) chk(file.exists(file.path(proc, u)), paste(u, "exists."), paste(u, "is missing (ignore if you ran with --skip-ui)."), "WARN")
cb <- codebook_path(root, ds)
chk(file.exists(cb), paste("Codebook exists:", cb),
    "Codebook not found (neither data/processed/df_codebook_<date>.rds nor df_codebook.rds in the repo root; ignore if you ran with --skip-ui).", "WARN")
if (fails) { cat("\nStopping: expected files missing.\n"); quit(status = 1) }

wide   <- readRDS(file.path(proc, f[["wide"]]))
filt   <- readRDS(file.path(proc, f[["filter"]]))
info   <- readRDS(file.path(proc, f[["info"]]))
rvu_d  <- readRDS(file.path(proc, f[["rvu"]]))
osf    <- readRDS(file.path(proc, f[["osf_rds"]]))
devs   <- read_xlsx(file.path(root, "data", "raw", "devices.xlsx"), na = na_vals)
if (is_partial(mode)) devs <- devs[devs$device_id %in% mode$devices, ]  # subset run: expect only these

# ---- row and key integrity ----
chk(nrow(wide) == nrow(devs), sprintf("Wide table has %d rows = devices in devices.xlsx.", nrow(wide)),
    sprintf("Wide table has %d rows but devices.xlsx has %d (devices lost or duplicated).", nrow(wide), nrow(devs)))
chk(!anyDuplicated(wide$device_id), "device_id unique in wide table.", "device_id duplicated in wide table.")
chk(identical(sort(wide$device_id), sort(devs[["device_id"]])), "Same device_ids as devices.xlsx.", "device_id set differs from devices.xlsx.")
chk(nrow(filt) == nrow(wide) && nrow(info) == nrow(wide) && nrow(osf) == nrow(wide),
    "Filter, info and OSF tables all have one row per device.", "Row counts differ between wide, filter, info and OSF tables.")
chk(setequal(c(setdiff(names(filt), "device_id"), names(info)), names(wide)) && identical(intersect(names(filt), names(info)), "device_id"),
    "Filter + info columns together cover the wide table; device_id is the only shared column.",
    "Filter and info columns do not cleanly split the wide table.")

# ---- filter columns the Shiny app expects (list is read from script 04a) ----
ex <- parse(file.path(root, "src", "application", "04a.sia.p1.wd.data.wide.to.shiny.R"))
pf <- NULL
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("product_filter_cols"))) pf <- eval(e[[3]])
if (!is.null(pf)) {
  m <- setdiff(pf, names(filt))
  chk(!length(m), sprintf("All %d expected filter columns present.", length(pf)),
      paste("Filter columns silently missing (source data lacks them):", paste(m, collapse = ", ")))
}

# ---- OSF table ----
na_cols <- names(osf)[vapply(osf, function(x) all(is.na(x)), logical(1))]
na_cols <- setdiff(na_cols, "Hyperlink to the device VRU page")  # intentionally empty in the script
chk(!length(na_cols), "No entirely empty OSF columns (apart from the intentionally empty hyperlink column).",
    paste("Entirely empty OSF columns:", paste(na_cols, collapse = ", ")), "WARN")

sheets <- excel_sheets(file.path(proc, f[["osf_xls"]]))
exp_sheets <- 1 + n_distinct(substr(rvu_d$device_id, 1, 31))
chk(sheets[1] == "df_osf_sia_wd", "OSF workbook: first sheet is df_osf_sia_wd.", "OSF workbook: first sheet name unexpected.")
chk(length(sheets) == exp_sheets, sprintf("OSF workbook has %d sheets (overview + one per device with detailed RVU studies).", length(sheets)),
    sprintf("OSF workbook has %d sheets, expected %d.", length(sheets), exp_sheets))
x1 <- read_xlsx(file.path(proc, f[["osf_xls"]]), sheet = 1)
chk(nrow(x1) == nrow(osf), "OSF Excel overview matches the OSF RDS row count.", "OSF Excel overview and OSF RDS differ in rows.")

# ---- plain facts for the reviewer step (no pass/fail) ----
cat("\n", paste(profile_facts(filt), collapse = "\n"), "\n", sep = "")

# ---- summary ----
cat("\nOutput folder:", proc, "\n")
cat(sprintf("Devices: %d | Wide columns: %d | Filter columns: %d | Info columns: %d | OSF columns: %d | OSF sheets: %d\n",
            nrow(wide), ncol(wide), ncol(filt), ncol(info), ncol(osf), length(sheets)))
cat(if (fails) sprintf("RESULT: %d check(s) FAILED.\n", fails) else "RESULT: all hard checks passed.\n")
if (is_partial(mode)) cat(PARTIAL_NOTE, "\n")
quit(status = if (fails) 1 else 0)
