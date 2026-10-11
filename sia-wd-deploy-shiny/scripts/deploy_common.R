# Shared helpers for the SiA-WD deploy skill. Base R only.
# Sourced by stage_files.R and upload_to_server.R.

# The 8 files the Shiny apps read, WITHOUT the date suffix (see global.R in
# the app repo and R/global.R in siawd). folder is relative to the app folder.
APP_FILES <- data.frame(
  folder = c("data", "data", "data", "data", "www", "www", "www", "www"),
  app_name = c("df_shiny_sia_wd_filter.rds", "df_shiny_sia_wd_info.rds",
               "df_shiny_rvu_detailed.rds", "df_osf_sia_wd_shiny.rds",
               "ui_constants.rds", "glos.rds", "df_codebook.rds", "updates.rds"),
  stringsAsFactors = FALSE
)

TARGETS <- c("test", "production", "siawd")

# Where each file comes from in the data repo. Note: no underscore before the
# date in the detailed RVU file (script 04a). The codebook exists in two
# layouts: dated in data/processed/ (05.ui_constants.R, stress-in-action) or
# undated in the repo root (older ui_constants.R). The dated one wins.
source_paths <- function(data_root, ds) {
  proc <- file.path(data_root, "data", "processed")
  codebook <- file.path(proc, paste0("df_codebook_", ds, ".rds"))
  if (!file.exists(codebook)) codebook <- file.path(data_root, "df_codebook.rds")
  c(
    file.path(proc, paste0("df_shiny_sia_wd_filter_", ds, ".rds")),
    file.path(proc, paste0("df_shiny_sia_wd_info_", ds, ".rds")),
    file.path(proc, paste0("df_shiny_rvu_detailed", ds, ".rds")),
    file.path(proc, paste0("df_osf_sia_wd_shiny_", ds, ".rds")),
    file.path(proc, paste0("ui_constants_", ds, ".rds")),
    file.path(proc, paste0("glos_", ds, ".rds")),
    codebook,
    file.path(proc, paste0("updates_", ds, ".rds"))
  )
}

# App folder per target: test/app and production/app in the Shiny repo,
# inst/app in the siawd golem package (read there through system.file()).
target_dir <- function(repo, target) {
  if (target == "siawd") file.path(repo, "inst", "app")
  else file.path(repo, target, "app")
}

app_paths <- function(repo, target) {
  file.path(target_dir(repo, target), APP_FILES$folder, APP_FILES$app_name)
}

# Same convention as the build skill: a missing file means an older FULL run.
read_run_mode <- function(data_root, ds) {
  p <- file.path(data_root, "data", "processed", paste0("run_mode_", ds, ".txt"))
  if (!file.exists(p)) return("FULL")
  l <- readLines(p, warn = FALSE)
  if (identical(sub("^mode=", "", l[1]), "PARTIAL")) "PARTIAL" else "FULL"
}

# Newest dated set in data/processed that comes from a FULL run, as YYYYMMDD
# (NA if none). PARTIAL sets are skipped, never deployed.
newest_ds <- function(data_root) {
  f <- list.files(file.path(data_root, "data", "processed"),
                  pattern = "^df_shiny_sia_wd_filter_[0-9]{8}\\.rds$")
  ds <- sort(sub("^df_shiny_sia_wd_filter_([0-9]{8})\\.rds$", "\\1", f),
             decreasing = TRUE)
  for (d in ds) if (read_run_mode(data_root, d) == "FULL") return(d)
  NA_character_
}

md5 <- function(paths) unname(tools::md5sum(paths))

# Positionals and --opt=value from the command line.
cli_opt <- function(args, name) {
  pat <- paste0("^--", name, "=")
  hit <- grep(pat, args, value = TRUE)
  if (length(hit)) sub(pat, "", hit[1]) else NULL
}
