# SiA-WD release diff: what changed against the previous release?
# Read-only apart from the two report files. Never fails the run (exit 0): the
# researcher confirms the changes are intended.
#
# Usage: Rscript release_diff.R <repo-root> [YYYYMMDD] [--prev=<YYYYMMDD|folder>]
#   Previous release = newest EARLIER dated set in data/processed/ that was a
#   full run, unless --prev names a date in data/processed/ or a folder that
#   holds a dated set. Subset runs only compare the selected devices.
# Writes data/processed/verification/release_diff_<date>[_partial].txt and .csv

source_dir <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
if (!exists("parse_cli")) source(file.path(source_dir(), "common.R"))

WIDE_PATTERN <- "^df_wide_sia_wd_([0-9]{8})\\.rds$"

dated_sets <- function(dir) {
  f <- list.files(dir, pattern = WIDE_PATTERN)
  sort(sub(WIDE_PATTERN, "\\1", f))
}

# list(dir, date) of the previous release, or NULL.
find_previous_release <- function(proc, ds, prev = NULL) {
  if (!is.null(prev)) {
    if (grepl("^[0-9]{8}$", prev)) {
      return(if (prev %in% dated_sets(proc)) list(dir = proc, date = prev))
    }
    sets <- if (dir.exists(prev)) dated_sets(prev) else character()
    return(if (length(sets)) list(dir = normalizePath(prev), date = max(sets)))
  }
  earlier <- dated_sets(proc)
  earlier <- earlier[earlier < ds]
  full <- vapply(earlier, function(d) !is_partial(read_run_mode(proc, d)), logical(1))
  earlier <- earlier[full]
  if (length(earlier)) list(dir = proc, date = max(earlier))
}

change_rows <- function(table, device_id, field, change, old, new) {
  n <- length(field)
  data.frame(table = rep(table, length.out = n),
             device_id = rep(device_id, length.out = n),
             field = field, change = rep(change, length.out = n),
             old = rep(old, length.out = n), new = rep(new, length.out = n),
             stringsAsFactors = FALSE)
}

# Changed cells between two keyed tables (rows present in both), plus columns
# added or removed. Row additions/removals only when report_rows = TRUE.
diff_tables <- function(old, new, table, report_rows = FALSE) {
  out <- list()
  both <- intersect(old$.key, new$.key)
  mo <- match(both, old$.key)
  mn <- match(both, new$.key)
  cols <- setdiff(intersect(names(old), names(new)), c("device_id", ".key"))
  for (cn in cols) {
    ok <- same_value(old[[cn]][mo], new[[cn]][mn])
    i <- which(!ok)
    out[[length(out) + 1]] <- change_rows(
      table, new$device_id[mn][i], rep(cn, length(i)), "changed",
      show_value(old[[cn]][mo][i]), show_value(new[[cn]][mn][i]))
  }
  for (cn in setdiff(names(new), c(names(old), ".key", "device_id")))
    out[[length(out) + 1]] <- change_rows(table, NA_character_, cn, "column_added", NA_character_, NA_character_)
  for (cn in setdiff(names(old), c(names(new), ".key", "device_id")))
    out[[length(out) + 1]] <- change_rows(table, NA_character_, cn, "column_removed", NA_character_, NA_character_)
  if (report_rows) {
    add <- setdiff(new$.key, old$.key)
    rem <- setdiff(old$.key, new$.key)
    out[[length(out) + 1]] <- change_rows(table, new$device_id[match(add, new$.key)], add, "row_added", NA_character_, NA_character_)
    out[[length(out) + 1]] <- change_rows(table, old$device_id[match(rem, old$.key)], rem, "row_removed", NA_character_, NA_character_)
  }
  out <- Filter(function(d) nrow(d) > 0, out)
  if (!length(out)) return(change_rows(character(), character(), character(), character(), character(), character()))
  res <- do.call(rbind, out)
  res[order(res$device_id, res$field, na.last = FALSE), ]
}

restrict <- function(d, ids) if (is.null(ids)) d else d[d$device_id %in% ids, , drop = FALSE]

# Compare the output tables that exist in both sets. Returns the change rows,
# the devices added/removed and notes about tables that could not be compared.
compare_releases <- function(old_files, new_files, ids = NULL) {
  read <- function(p) if (file.exists(p)) as.data.frame(readRDS(p), stringsAsFactors = FALSE)
  old_w <- restrict(read(old_files[["wide"]]), ids)
  new_w <- restrict(read(new_files[["wide"]]), ids)
  tables <- list(
    "Shiny filter" = c("filter", FALSE), "Shiny info" = c("info", FALSE),
    "OSF overview" = c("osf_rds", FALSE), "Detailed RVU studies" = c("rvu", TRUE))
  changes <- list()
  notes <- character()
  for (nm in names(tables)) {
    key <- tables[[nm]][1]
    by_study <- tables[[nm]][2] == "TRUE"
    o <- read(old_files[[key]])
    n <- read(new_files[[key]])
    if (is.null(o) || is.null(n)) {
      notes <- c(notes, sprintf("%s not compared: missing in the %s release.", nm,
                                if (is.null(o)) "previous" else "new"))
      next
    }
    changes[[nm]] <- diff_tables(add_key(restrict(o, ids), by_study),
                                 add_key(restrict(n, ids), by_study), nm, by_study)
  }
  added <- setdiff(new_w$device_id, old_w$device_id)
  removed <- setdiff(old_w$device_id, new_w$device_id)
  changes[["Devices"]] <- rbind(
    change_rows("Devices", added, rep("<device>", length(added)),
                "device_added", NA_character_, NA_character_),
    change_rows("Devices", removed, rep("<device>", length(removed)),
                "device_removed", NA_character_, NA_character_))
  list(changes = do.call(rbind, unname(changes)), added = added,
       removed = removed, new_wide = new_w, old_wide = old_w, notes = notes)
}

label_devices <- function(ids, wide) {
  if (!length(ids)) return("none")
  m <- match(ids, wide$device_id)
  nm <- ifelse(is.na(m), "", paste0(" (", wide$manufacturer[m], " ", wide$model[m], ")"))
  paste0(ids, nm)
}

clip <- function(x, n = 80) ifelse(nchar(x) > n, paste0(substr(x, 1, n - 3), "..."), x)

format_report <- function(diff, ds, prev_date, mode, ids) {
  ch <- diff$changes
  L <- sprintf("SiA-WD release diff: %s against previous release %s", ds, prev_date)
  if (is_partial(mode)) {
    L <- c(L, PARTIAL_NOTE,
           sprintf("Compared only %d selected device(s); other devices are never reported as removed.", length(ids)))
  }
  old_lab <- diff$old_wide
  L <- c(L, "", sprintf("Devices added (%d):", length(diff$added)),
         paste0("  ", label_devices(diff$added, diff$new_wide)),
         sprintf("Devices removed (%d):", length(diff$removed)),
         paste0("  ", label_devices(diff$removed, old_lab)))
  L <- c(L, "", sprintf("Fields changed: %d across %d device(s)",
                        sum(ch$change == "changed"), length(unique(ch$device_id[ch$change == "changed"]))))
  for (tb in setdiff(unique(ch$table), "Devices")) {
    x <- ch[ch$table == tb, ]
    L <- c(L, "", sprintf("== %s: %d change(s) ==", tb, nrow(x)))
    top <- sort(table(x$field[x$change == "changed"]), decreasing = TRUE)
    if (length(top)) L <- c(L, "Most changed fields: " ,
                            paste0("  ", names(top), ": ", top, " device(s)")[seq_len(min(5, length(top)))])
    L <- c(L, ifelse(x$change == "changed",
                     sprintf("  %s | %s | %s -> %s", x$device_id, x$field, clip(x$old), clip(x$new)),
                     sprintf("  %s | %s | %s", ifelse(is.na(x$device_id), "(all)", x$device_id), x$field, x$change)))
  }
  c(L, "", diff$notes, "","This report does not fail the run. Please confirm every change above is intended.")
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  cli <- parse_cli(args)
  proc <- file.path(cli$root, "data", "processed")
  mode <- read_run_mode(proc, cli$ds)
  new_files <- output_paths(proc, cli$ds)
  if (!file.exists(new_files[["wide"]])) stop("No outputs for ", cli$ds, " in ", proc)
  prev <- find_previous_release(proc, cli$ds, cli$prev)
  if (is.null(prev)) {
    cat("No previous release found (no earlier full set in data/processed/ and no --prev given).\nRelease diff skipped.\n")
    quit(status = 0L)
  }
  ids <- mode$devices  # NULL for a full run
  diff <- compare_releases(output_paths(prev$dir, prev$date), new_files, ids)
  lines <- format_report(diff, cli$ds, prev$date, mode, ids)
  writeLines(lines)
  vdir <- file.path(proc, "verification")
  dir.create(vdir, showWarnings = FALSE)
  stem <- file.path(vdir, paste0("release_diff_", cli$ds, report_suffix(mode)))
  writeLines(lines, paste0(stem, ".txt"))
  utils::write.csv(diff$changes, paste0(stem, ".csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  quit(status = 0L)
}

if (sys.nframe() == 0L) main()
