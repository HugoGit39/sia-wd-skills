# SiA-WD run: executes the repo scripts in their documented order, in one R session.
# Usage: Rscript run_pipeline.R <path-to-repo-root> [--skip-ui]
#          [--devices=id1,id2 | --devices-file=path]
# Writes dated files into <root>/data/processed (the codebook too with 05.ui_constants.R;
# the older ui_constants.R writes df_codebook.rds into <root>).
# Never pushes, uploads or deploys anything.
#
# Subset mode (--devices / --devices-file): the repo scripts stay untouched.
# Right after the read step (02) this wrapper applies the same filter as the
# commented DEVICE_FILTER block in script 02, to all seven tables (the repo
# block skips rvu_detailed, which would leak every device into the Shiny
# detailed-RVU file and the OSF device sheets). Steps 03 to 05 then see only
# the chosen devices because they read the objects 02 created. The run is
# recorded in data/processed/run_mode_<date>.txt so later checks know it is
# PARTIAL.

script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])))
source(file.path(script_dir, "common.R"))

cli <- parse_cli(commandArgs(trailingOnly = TRUE))
root <- normalizePath(cli$root, mustWork = TRUE)
setwd(root)  # the scripts build paths with here(), which resolves from the repo root

apply_subset <- function(ids) {
  tabs <- mget(names(MOTHER_FILES), envir = globalenv())
  gone <- missing_devices(tabs, ids)
  bad <- gone[gone$table %in% c("devices", "scores"), ]
  if (nrow(bad)) {
    stop("Requested device_id not found in ", paste(unique(bad$table), collapse = ", "),
         ": ", paste(unique(bad$device_id), collapse = ", "))
  }
  assign("DEVICE_FILTER", ids, envir = globalenv())
  list2env(apply_device_filter(tabs, ids), envir = globalenv())
  cat(sprintf("PARTIAL RUN: %d device(s) selected: %s\n", length(ids), paste(ids, collapse = ", ")))
}

start_date <- Sys.Date()
steps <- c(
  "01 packages"         = "src/application/01.sia.p1.packages.R",
  "02 read mother tables" = "src/application/02.sia.p1.read.data.R",
  "03 build wide table" = "src/application/03.sia.p1.wd.data.wide.R",
  "04a Shiny data frames" = "src/application/04a.sia.p1.wd.data.wide.to.shiny.R",
  "04b OSF export"      = "src/application/04b.sia.p1.wd.data.wide.to.osf.R"
)
if (!cli$skip_ui) {
  ui <- ui_script(root)
  if (is.na(ui)) stop("No UI script found (", paste(UI_SCRIPTS, collapse = " or "), "). Use --skip-ui or fix the clone.")
  steps <- c(steps, "05 Shiny UI objects (ui_constants)" = ui)
}

for (i in seq_along(steps)) {
  cat(sprintf("\n=== Step %d/%d: %s ===\n", i, length(steps), names(steps)[i]))
  if (names(steps)[i] == "05 Shiny UI objects (ui_constants)") {
    suppressPackageStartupMessages(library(shiny))  # ui_constants.R uses div(), p(), tagList()
  }
  ok <- tryCatch({
    if (startsWith(names(steps)[i], "03") ) {
      # filter after the read step, before anything is built or written
      if (!is.null(cli$devices)) apply_subset(cli$devices)
      write_run_mode(file.path(root, "data", "processed"), format(start_date, "%Y%m%d"), cli$devices)
    }
    source(steps[[i]], local = FALSE, echo = FALSE)
    TRUE
  }, error = function(e) {
    cat(sprintf("FAILED in step '%s': %s\n", names(steps)[i], conditionMessage(e)))
    FALSE
  })
  if (!ok) quit(status = 1)
  cat("done.\n")
}

if (Sys.Date() != start_date)
  cat("\nWARNING: the date changed during the run. Scripts 04a/04b read the wide file dated 'today', so files may carry different dates. Rerun in one go.\n")
cat("\nDate suffix used:", format(start_date, "%Y%m%d"), "\n")
if (!is.null(cli$devices)) cat(PARTIAL_NOTE, "\n")
cat("Pipeline finished. Next: run validate.R, roundtrip.R and release_diff.R.\n")
