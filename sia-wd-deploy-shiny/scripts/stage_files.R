#!/usr/bin/env Rscript
# Copy the 8 Shiny RDS files from the data repo into an app folder, dropping
# the date from the names, and verify every copy by checksum.
#
# Usage: Rscript stage_files.R <data_repo> <repo> <test|production|siawd> [YYYYMMDD]
#   test, production : <repo> is the Shiny app repo, files go to <target>/app
#   siawd            : <repo> is the siawd golem package, files go to inst/app
# Touches only the 8 files. Never touches global.R or any code.

script_dir <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), mustWork = FALSE))
source(file.path(script_dir, "deploy_common.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript stage_files.R <data_repo> <repo> <test|production|siawd> [YYYYMMDD]")
}
data_root <- normalizePath(args[1], mustWork = TRUE)
repo      <- normalizePath(args[2], mustWork = TRUE)
target    <- args[3]
if (!target %in% TARGETS) stop("target must be one of: ", paste(TARGETS, collapse = ", "))
ds <- if (length(args) >= 4) args[4] else newest_ds(data_root)
if (is.na(ds)) stop("No FULL df_shiny_sia_wd_filter_<date>.rds found in data/processed/")

app_dir <- target_dir(repo, target)
if (target == "siawd") {
  desc <- file.path(repo, "DESCRIPTION")
  if (!file.exists(desc) || !any(readLines(desc, warn = FALSE) == "Package: siawd")) {
    stop("Not the siawd package (no DESCRIPTION with 'Package: siawd'): ", repo)
  }
} else if (!file.exists(file.path(app_dir, "app.R"))) {
  stop("Not an app folder (no app.R): ", app_dir)
}
if (read_run_mode(data_root, ds) != "FULL") {
  stop("Run ", ds, " is PARTIAL. Not for the app. Rebuild with all devices first.")
}

src <- source_paths(data_root, ds)
dst <- app_paths(repo, target)
missing <- src[!file.exists(src)]
if (length(missing)) {
  stop("Missing source files:\n  ", paste(missing, collapse = "\n  "))
}
for (d in unique(dirname(dst))) {
  if (!dir.exists(d)) stop("App folder missing: ", d)
}

cat("Staging data set", ds, "into", app_dir, "\n")
ok <- file.copy(src, dst, overwrite = TRUE)
same <- md5(src) == md5(dst)
res <- data.frame(file = file.path(APP_FILES$folder, APP_FILES$app_name),
                  copied = ok, checksum_ok = same)
print(res, row.names = FALSE)
if (!all(ok & same)) stop("Copy or checksum failed for at least one file.")

if (target == "production") {
  test_files <- app_paths(repo, "test")
  if (all(file.exists(test_files)) && !all(md5(test_files) == md5(dst))) {
    cat("\nWARNING: test/app and production/app hold different data files.",
        "Stage test first and confirm it.\n")
  }
}
cat("\nDONE: 8 files of", ds, "staged in", target, "\n")
