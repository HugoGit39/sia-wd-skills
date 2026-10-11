#!/usr/bin/env Rscript
# Raise the patch number of the siawd package version (1.0.0 -> 1.0.1) so that
# users who reinstall can see they have the new data. Changes only the
# 'Version:' line of DESCRIPTION, nothing else in the file.
#
# Usage: Rscript bump_siawd_version.R <siawd_repo> [--dry-run]
# Prints: OLD=<x.y.z> NEW=<x.y.z+1> TAG=v<x.y.z+1>

args <- commandArgs(trailingOnly = TRUE)
pos <- args[!startsWith(args, "--")]
if (length(pos) < 1) stop("Usage: Rscript bump_siawd_version.R <siawd_repo> [--dry-run]")
desc <- file.path(normalizePath(pos[1], mustWork = TRUE), "DESCRIPTION")
if (!file.exists(desc)) stop("No DESCRIPTION in ", pos[1])

lines <- readLines(desc, warn = FALSE, encoding = "UTF-8")
if (!any(lines == "Package: siawd")) stop("DESCRIPTION is not the siawd package.")
at <- grep("^Version:", lines)
if (length(at) != 1) stop("Expected exactly one 'Version:' line in DESCRIPTION.")
old <- trimws(sub("^Version:", "", lines[at]))
if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", old)) {
  stop("Version '", old, "' is not plain x.y.z (development version?). Ask before changing it.")
}
p <- as.integer(strsplit(old, ".", fixed = TRUE)[[1]])
new <- paste(p[1], p[2], p[3] + 1L, sep = ".")

if (!"--dry-run" %in% args) {
  lines[at] <- paste("Version:", new)
  con <- file(desc, open = "wb")  # keep LF line endings, no BOM
  writeLines(lines, con, sep = "\n", useBytes = TRUE)
  close(con)
}
cat("OLD=", old, " NEW=", new, " TAG=v", new, if ("--dry-run" %in% args) " (dry run)", "\n", sep = "")
