#!/usr/bin/env Rscript
# Check that every R package the apps load is installed, before starting them.
# Reads the lists from the source, so they never go stale:
#   required_packages <- c(...) in test/app/global.R and production/app/global.R
#   Imports in the siawd DESCRIPTION (plus pkgload, used to run it locally)
#
# Usage: Rscript check_packages.R <app_repo> [<siawd_repo>] [--install]
# Prints PACKAGES_OK, or the missing packages and the install line (exit 1).
# --install installs the missing ones from CRAN (only after the researcher said yes).

args <- commandArgs(trailingOnly = TRUE)
pos <- args[!startsWith(args, "--")]
if (length(pos) < 1) stop("Usage: Rscript check_packages.R <app_repo> [<siawd_repo>] [--install]")

# The c("a", "b") assigned to required_packages, accepted only if every
# element is a plain string, so nothing from the file is executed.
global_pkgs <- function(path) {
  if (!file.exists(path)) stop("Not found: ", path)
  for (e in parse(path, keep.source = FALSE)) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        identical(e[[2]], as.name("required_packages"))) {
      rhs <- as.list(e[[3]])
      if (identical(rhs[[1]], as.name("c")) &&
          all(vapply(rhs[-1], is.character, logical(1)))) {
        return(unlist(rhs[-1]))
      }
    }
  }
  stop("No plain required_packages <- c(...) in ", path)
}

desc_imports <- function(repo) {
  d <- read.dcf(file.path(repo, "DESCRIPTION"), fields = "Imports")[1, 1]
  if (is.na(d)) return(character())
  p <- trimws(sub("\\(.*$", "", strsplit(d, ",")[[1]]))
  p[nzchar(p)]
}

need <- c(global_pkgs(file.path(pos[1], "test", "app", "global.R")),
          global_pkgs(file.path(pos[1], "production", "app", "global.R")))
if (length(pos) >= 2) need <- c(need, desc_imports(pos[2]), "pkgload")
need <- sort(unique(need))
missing <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]

if (!length(missing)) {
  cat("PACKAGES_OK:", length(need), "packages installed\n")
  quit(save = "no", status = 0)
}
line <- sprintf('install.packages(c(%s), repos = "https://cloud.r-project.org")',
                paste0('"', missing, '"', collapse = ", "))
cat("MISSING:", paste(missing, collapse = ", "), "\n")
if ("--install" %in% args) {
  install.packages(missing, repos = "https://cloud.r-project.org")
  still <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still)) {
    cat("STILL_MISSING:", paste(still, collapse = ", "), "\n")
    quit(save = "no", status = 1)
  }
  cat("PACKAGES_OK: installed", length(missing), "\n")
  quit(save = "no", status = 0)
}
cat("INSTALL_LINE:", line, "\n")
quit(save = "no", status = 1)
