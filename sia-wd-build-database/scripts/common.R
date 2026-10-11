# Shared helpers for the SiA-WD skill scripts. Base R only (no package needed
# to source this file), except read_mother_tables() which needs readxl + janitor
# exactly like the repo's own read step.
# Sourced by preflight.R, run_pipeline.R, validate.R, roundtrip.R, release_diff.R.

NA_TOKENS <- c("", "NA", "NP", "N/A", "Na", "na", "NULL", "-9999")  # = script 02

# Object name used by the repo scripts -> mother table file name.
MOTHER_FILES <- c(
  devices      = "devices.xlsx",
  signals_long = "signals.xlsx",
  specs        = "technical_specs.xlsx",
  data_access  = "data_access.xlsx",
  rvu          = "rvu_synthesis.xlsx",
  scores       = "expert_scores.xlsx",
  rvu_detailed = "rvu_synthesis_detailed.xlsx"
)

PARTIAL_NOTE <- paste(
  "PARTIAL RUN: only the selected devices were built.",
  "NOT for publication to Shiny or OSF."
)

# ---- command line -----------------------------------------------------------

# Options: --devices=a,b  --devices-file=path  --prev=<YYYYMMDD|folder>
# Positionals: ROOT, then an optional YYYYMMDD date (default today).
parse_cli <- function(args) {
  opt <- function(name) {
    pat <- paste0("^--", name, "=")
    hit <- grep(pat, args, value = TRUE)
    if (length(hit)) sub(pat, "", hit[1]) else NULL
  }
  pos <- args[!startsWith(args, "--")]
  rest <- pos[-1]
  ds <- rest[grepl("^[0-9]{8}$", rest)][1]
  list(
    root = normalizePath(if (length(pos)) pos[1] else getwd(),
                         mustWork = FALSE),
    ds = if (is.na(ds)) format(Sys.Date(), "%Y%m%d") else ds,
    devices = read_device_ids(opt("devices"), opt("devices-file")),
    prev = opt("prev"),
    skip_ui = "--skip-ui" %in% args
  )
}

# A comma list and/or a text file (one id per line, '#' comments allowed).
read_device_ids <- function(csv = NULL, file = NULL) {
  if (is.null(csv) && is.null(file)) return(NULL)
  txt <- character()
  if (!is.null(csv)) txt <- c(txt, csv)
  if (!is.null(file)) {
    if (!file.exists(file)) stop("Device list file not found: ", file)
    lines <- readLines(file, warn = FALSE, encoding = "UTF-8")
    txt <- c(txt, sub("#.*$", "", lines))
  }
  ids <- trimws(unlist(strsplit(txt, "[,;[:space:]]+")))
  ids <- unique(ids[nzchar(ids)])
  if (!length(ids)) stop("The device selection is empty.")
  ids
}

# ---- paths and run mode -----------------------------------------------------

# Output file names as the repo scripts write them (note: no underscore before
# the date in the detailed RVU file, as in script 04a).
output_paths <- function(dir, ds) {
  c(
    wide    = file.path(dir, paste0("df_wide_sia_wd_", ds, ".rds")),
    filter  = file.path(dir, paste0("df_shiny_sia_wd_filter_", ds, ".rds")),
    info    = file.path(dir, paste0("df_shiny_sia_wd_info_", ds, ".rds")),
    rvu     = file.path(dir, paste0("df_shiny_rvu_detailed", ds, ".rds")),
    osf_rds = file.path(dir, paste0("df_osf_sia_wd_shiny_", ds, ".rds")),
    osf_xls = file.path(dir, paste0("df_osf_sia_wd_", ds, ".xlsx"))
  )
}

# The repo exists in two layouts. stress-in-action: UI step is
# 05.ui_constants.R and writes the codebook dated into data/processed/.
# Older copy: ui_constants.R writes an undated df_codebook.rds in the root.
UI_SCRIPTS <- c("src/application/05.ui_constants.R", "src/application/ui_constants.R")

# Relative path of the UI step present in this clone, NA if neither exists.
ui_script <- function(root) {
  hit <- UI_SCRIPTS[file.exists(file.path(root, UI_SCRIPTS))]
  if (length(hit)) hit[1] else NA_character_
}

# The codebook a run wrote: dated in data/processed/ wins, else the root file.
codebook_path <- function(root, ds) {
  dated <- file.path(root, "data", "processed", paste0("df_codebook_", ds, ".rds"))
  if (file.exists(dated)) dated else file.path(root, "df_codebook.rds")
}

run_mode_path <- function(proc, ds) {
  file.path(proc, paste0("run_mode_", ds, ".txt"))
}

# Written by run_pipeline.R. Missing file means a full run (older runs).
write_run_mode <- function(proc, ds, devices = NULL) {
  lines <- if (is.null(devices)) {
    c("mode=FULL", "All devices in the mother tables were built.")
  } else {
    c("mode=PARTIAL", PARTIAL_NOTE, "devices:", devices)
  }
  writeLines(lines, run_mode_path(proc, ds), useBytes = TRUE)
}

read_run_mode <- function(proc, ds) {
  p <- run_mode_path(proc, ds)
  if (!file.exists(p)) return(list(mode = "FULL", devices = NULL))
  l <- readLines(p, warn = FALSE)
  at <- match("devices:", l)
  ids <- if (!is.na(at) && at < length(l)) l[(at + 1):length(l)] else NULL
  mode <- if (identical(sub("^mode=", "", l[1]), "PARTIAL")) "PARTIAL" else "FULL"
  list(mode = mode, devices = if (mode == "PARTIAL") ids else NULL)
}

is_partial <- function(mode) identical(mode$mode, "PARTIAL")
report_suffix <- function(mode) if (is_partial(mode)) "_partial" else ""

# ---- device subset ----------------------------------------------------------

# Same restriction as the commented DEVICE_FILTER block in script 02, but for
# all seven tables (the repo block leaves out rvu_detailed).
apply_device_filter <- function(tables, ids) {
  lapply(tables, function(d) d[d$device_id %in% ids, , drop = FALSE])
}

# One row per (table, requested id) that is absent from that table.
missing_devices <- function(tables, ids) {
  out <- lapply(names(tables), function(nm) {
    gone <- setdiff(ids, tables[[nm]]$device_id)
    data.frame(table = rep(nm, length(gone)), device_id = gone,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

# Read the seven mother tables the way script 02 does.
read_mother_tables <- function(root) {
  stopifnot(requireNamespace("readxl", quietly = TRUE),
            requireNamespace("janitor", quietly = TRUE))
  read_one <- function(file) {
    d <- readxl::read_xlsx(file.path(root, "data", "raw", file),
                           na = NA_TOKENS)
    janitor::clean_names(d)
  }
  lapply(MOTHER_FILES, read_one)
}

# ---- value comparison -------------------------------------------------------

to_cmp <- function(x) {
  if (inherits(x, "POSIXt")) return(format(x, "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  if (is.factor(x) || is.logical(x)) return(as.character(x))
  x
}

# Element-wise equality. Both empty = equal. Numbers use a tiny relative
# tolerance (Excel round trips); text must match exactly.
same_value <- function(a, b) {
  a <- to_cmp(a)
  b <- to_cmp(b)
  na_a <- is.na(a)
  na_b <- is.na(b)
  out <- na_a & na_b
  both <- !na_a & !na_b
  if (!any(both)) return(out)
  if (is.numeric(a) || is.numeric(b)) {
    x <- suppressWarnings(as.numeric(a))
    y <- suppressWarnings(as.numeric(b))
    eq <- abs(x - y) <= 1e-9 * pmax(1, abs(x), abs(y))
  } else {
    eq <- as.character(a) == as.character(b)
  }
  eq[is.na(eq)] <- FALSE
  out[both] <- eq[both]
  out
}

# Row key: device_id, plus the citation (and its occurrence) for study tables.
add_key <- function(d, by_study = FALSE) {
  d <- as.data.frame(d, stringsAsFactors = FALSE)
  if (!by_study) {
    d$.key <- d$device_id
    return(d)
  }
  cite <- if ("study_citation" %in% names(d)) as.character(d$study_citation) else ""
  base <- paste(d$device_id, cite, sep = " | ")
  d$.key <- paste0(base, " #", stats::ave(seq_along(base), base, FUN = seq_along))
  d
}

show_value <- function(x) {
  x <- to_cmp(x)
  out <- as.character(x)
  out[is.na(x)] <- "<empty>"
  out
}

# ---- plausibility facts (feed the reviewer step) ----------------------------

# Plain facts about the filter table: score range, year range, numeric ranges
# with the device holding the extremes, and devices with many empty fields.
profile_facts <- function(filt, this_year = as.integer(format(Sys.Date(), "%Y"))) {
  lines <- "Plausibility facts (filter table):"
  num <- names(filt)[vapply(filt, is.numeric, logical(1))]
  for (cn in num) {
    v <- filt[[cn]]
    if (all(is.na(v))) next
    lo <- which.min(v)
    hi <- which.max(v)
    lines <- c(lines, sprintf(
      "  %s: min %s (%s), median %s, max %s (%s), %d empty",
      cn, format(min(v, na.rm = TRUE)), filt$device_id[lo],
      format(stats::median(v, na.rm = TRUE)), format(max(v, na.rm = TRUE)),
      filt$device_id[hi], sum(is.na(v))))
  }
  sc <- grep("_score$", names(filt), value = TRUE)
  for (cn in sc) {
    bad <- filt$device_id[!is.na(filt[[cn]]) & (filt[[cn]] < 0 | filt[[cn]] > 10)]
    if (length(bad))
      lines <- c(lines, sprintf("  SCORE OUTSIDE 0-10 in %s: %s", cn,
                                paste(bad, collapse = ", ")))
  }
  if ("release_year" %in% names(filt)) {
    yr <- release_year_of(filt$release_year)
    bad <- filt$device_id[!is.na(yr) & (yr > this_year | yr < 1990)]
    if (length(bad))
      lines <- c(lines, sprintf("  release_year in the future or before 1990: %s",
                                paste(bad, collapse = ", ")))
  }
  empty_share <- rowMeans(is.na(filt[setdiff(names(filt), "device_id")]))
  top <- order(empty_share, decreasing = TRUE)[seq_len(min(5, nrow(filt)))]
  lines <- c(lines, "  Devices with the most empty filter fields:",
             sprintf("    %s: %.0f%% empty", filt$device_id[top],
                     100 * empty_share[top]))
  lines
}

release_year_of <- function(x) {
  if (inherits(x, "POSIXt")) return(as.integer(format(x, "%Y")))
  suppressWarnings(as.integer(x))
}
