#!/usr/bin/env Rscript
# Upload the 8 production Shiny RDS files to the live server over SSH.
#
# Usage: Rscript upload_to_server.R <app_repo> --check [--conf=path]
#        Rscript upload_to_server.R <app_repo> --upload [--conf=path]
#
# --check  : config, SSH login (no prompt), server folder layout, local files.
# --upload : --check, then backup of the 8 remote files, scp, checksum
#            compare, optional restart command.
# Exit status: 0 ok, 2 SSH failed, 3 server folder wrong, 4 local or config
# problem, 5 upload or checksum failed, 6 files uploaded but restart/reload
# of Shiny Server or nginx failed or is not configured, 7 no write rights on
# the server folder or files (found by --check, before anything is changed).
# No passwords are used (BatchMode). The conf file holds no secrets.

script_dir <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), mustWork = FALSE))
source(file.path(script_dir, "deploy_common.R"))

args <- commandArgs(trailingOnly = TRUE)
pos <- args[!startsWith(args, "--")]
if (length(pos) < 1 || !any(c("--check", "--upload") %in% args)) {
  stop("Usage: Rscript upload_to_server.R <app_repo> --check|--upload [--conf=path]")
}
upload <- "--upload" %in% args
# Forward slashes: scp must not read "C:\..." as host "C".
app_repo <- normalizePath(pos[1], winslash = "/", mustWork = TRUE)
conf_path <- cli_opt(args, "conf")
if (is.null(conf_path)) conf_path <- path.expand("~/.sia_wd_deploy.conf")

die <- function(code, ...) {
  cat(..., "\n", sep = "")
  quit(save = "no", status = code)
}

# ---- ssh and scp ------------------------------------------------------------
# On Windows prefer the built-in OpenSSH client: the copies that come with Git
# (MSYS) can read a local "C:/..." path as a remote host called "C".
find_bin <- function(name) {
  if (.Platform$OS.type == "windows") {
    win <- file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "OpenSSH",
                     paste0(name, ".exe"))
    if (file.exists(win)) return(normalizePath(win, winslash = "/"))
  }
  unname(Sys.which(name))
}
ssh_bin <- find_bin("ssh")
scp_bin <- find_bin("scp")
if (!nzchar(ssh_bin) || !nzchar(scp_bin)) {
  die(4, "SSH_MISSING: no ssh/scp client found. Install the OpenSSH client ",
      "(references/ssh_setup.md, step 2).")
}

# ---- config -----------------------------------------------------------------
if (!file.exists(conf_path)) {
  die(4, "CONFIG_MISSING: ", conf_path,
      "\nCreate it from references/server_config.template.txt.")
}
lines <- trimws(readLines(conf_path, warn = FALSE))
lines <- lines[nzchar(lines) & !startsWith(lines, "#") & grepl("=", lines)]
conf <- setNames(trimws(sub("^[^=]*=", "", lines)),
                 trimws(sub("=.*$", "", lines)))
need <- c("host", "user", "remote_app_dir")
bad <- need[is.na(conf[need]) | !nzchar(conf[need])]
if (length(bad)) die(4, "CONFIG_INCOMPLETE: fill in ", paste(bad, collapse = ", "))

safe <- "^[A-Za-z0-9_./~-]+$"
if (!grepl(safe, conf[["remote_app_dir"]])) {
  die(4, "CONFIG_INVALID: remote_app_dir may only hold letters, digits and _ . / ~ -")
}
if (!grepl("^[A-Za-z0-9_.-]+$", conf[["host"]]) ||
    !grepl("^[A-Za-z0-9_.-]+$", conf[["user"]])) {
  die(4, "CONFIG_INVALID: host and user may only hold letters, digits and _ . -")
}
remote <- sub("/+$", "", conf[["remote_app_dir"]])
port <- if (!is.na(conf["port"]) && nzchar(conf["port"])) conf[["port"]] else "22"
key  <- if (!is.na(conf["key"]) && nzchar(conf["key"])) {
  normalizePath(path.expand(conf[["key"]]), winslash = "/", mustWork = FALSE)
} else NULL
opt_key <- function(k) if (!is.na(conf[k]) && nzchar(conf[k])) conf[[k]] else ""
restart_shiny <- opt_key("restart_shiny_command")
reload_nginx  <- opt_key("reload_nginx_command")
target <- paste0(conf[["user"]], "@", conf[["host"]])

ssh_opts <- c("-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
              "-o", "StrictHostKeyChecking=accept-new")
if (!is.null(key)) ssh_opts <- c(ssh_opts, "-i", shQuote(key))

run_ssh <- function(cmd) {
  out <- suppressWarnings(system2(ssh_bin,
    c(ssh_opts, "-p", port, target, shQuote(cmd)), stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

# ---- local files ------------------------------------------------------------
local_files <- app_paths(app_repo, "production")
gone <- local_files[!file.exists(local_files)]
if (length(gone)) {
  die(4, "LOCAL_MISSING: stage the production files first:\n  ",
      paste(gone, collapse = "\n  "))
}

# ---- ssh login --------------------------------------------------------------
cat("Checking SSH login to", target, "...\n")
r <- run_ssh("echo SSH_OK")
if (r$status != 0 || !any(grepl("SSH_OK", r$out))) {
  txt <- paste(r$out, collapse = " ")
  why <- if (grepl("timed out|Could not resolve|No route|refused", txt, ignore.case = TRUE)) {
    "Server not reachable. Connect to the VU network or VPN first."
  } else if (grepl("Permission denied", txt, ignore.case = TRUE)) {
    "Server reachable, but no key login. Set up an SSH key (references/ssh_setup.md)."
  } else {
    "SSH failed. See references/ssh_setup.md."
  }
  die(2, "SSH_FAIL: ", why, "\nssh said: ", txt)
}
cat("  SSH login works.\n")

# ---- server layout ----------------------------------------------------------
lay <- run_ssh(sprintf(
  "test -f %s/app.R && test -f %s/global.R && test -d %s/data && test -d %s/www && echo LAYOUT_OK",
  remote, remote, remote, remote))
if (!any(grepl("LAYOUT_OK", lay$out))) {
  die(3, "LAYOUT_FAIL: ", remote, " on the server does not look like the app folder ",
      "(needs app.R, global.R, data/, www/). Fix remote_app_dir in ", conf_path)
}
cat("  Server folder looks right:", remote, "\n")

# ---- write rights -----------------------------------------------------------
# The backup folder goes into <remote>, the files into data/ and www/. An
# existing file must be writable; a missing one only needs a writable folder.
rel <- paste0(APP_FILES$folder, "/", APP_FILES$app_name)
wr <- c(sprintf("test -w %s", c(remote, paste0(remote, "/data"), paste0(remote, "/www"))),
        sprintf("{ [ ! -e %s/%s ] || test -w %s/%s; }", remote, rel, remote, rel))
wchk <- run_ssh(paste(c(wr, "echo WRITE_OK"), collapse = " && "))
if (!any(grepl("WRITE_OK", wchk$out))) {
  die(7, "WRITE_FAIL: your account cannot write ", remote, " or its data/ www/ files. ",
      "Nothing was changed. Ask the server admin for write rights on those (see ",
      "references/ssh_setup.md).")
}
cat("  Write rights OK.\n")

if (!upload) {
  cat("\nCHECK_OK: ready to upload 8 files from production/app.\n")
  quit(save = "no", status = 0)
}

# ---- backup -----------------------------------------------------------------
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
bdir <- paste0(remote, "/_backup_", ts)
# Chained with &&: BACKUP_DONE prints only if mkdir and every copy worked.
cp <- sprintf("{ [ ! -f %s/%s ] || cp -p %s/%s %s/%s/; }",
              remote, rel, remote, rel, bdir, APP_FILES$folder)
bk <- run_ssh(paste(c(sprintf("mkdir -p %s/data %s/www", bdir, bdir), cp,
                      "echo BACKUP_DONE"), collapse = " && "))
if (!any(grepl("BACKUP_DONE", bk$out))) die(5, "BACKUP_FAIL: nothing was uploaded.")
cat("  Backup written to", bdir, "\n")

# ---- upload and verify ------------------------------------------------------
scp_opts <- c("-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-P", port)
if (!is.null(key)) scp_opts <- c(scp_opts, "-i", shQuote(key))
failed <- character()
for (i in seq_along(local_files)) {
  dest <- paste0(target, ":", remote, "/", rel[i])
  st <- suppressWarnings(system2(scp_bin, c(scp_opts, shQuote(local_files[i]), dest),
                                 stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(st, "status")) && attr(st, "status") != 0) failed <- c(failed, rel[i])
}
if (length(failed)) {
  die(5, "UPLOAD_FAIL: ", paste(failed, collapse = ", "),
      "\nThe server may now hold a mix. Restore from ", bdir)
}
sums <- run_ssh(paste0("cd ", remote, " && md5sum ", paste(rel, collapse = " ")))
rem <- setNames(sub(" .*$", "", sums$out), sub("^[0-9a-f]+ +\\*?", "", sums$out))
loc <- setNames(md5(local_files), rel)
res <- data.frame(file = rel, match = !is.na(rem[rel]) & rem[rel] == loc[rel])
print(res, row.names = FALSE)
if (!all(res$match)) {
  die(5, "CHECKSUM_FAIL: server files differ from local. Restore from ", bdir)
}
cat("  All 8 files match by checksum.\n")

# ---- restart Shiny Server, then reload nginx --------------------------------
# Two separate commands from the config, run in this order. The files are
# already on the server when these run, so a failure here is exit 6, not 5.
restart_failed <- character()
for (step in list(list("Shiny Server restart", restart_shiny),
                  list("nginx reload", reload_nginx))) {
  if (!nzchar(step[[2]])) {
    cat("  ", step[[1]], ": no command in the config, skipped.\n", sep = "")
    restart_failed <- c(restart_failed, paste(step[[1]], "(not configured)"))
    next
  }
  rs <- run_ssh(step[[2]])
  cat("  ", step[[1]], ": exit ", rs$status, "\n", sep = "")
  if (rs$status != 0) {
    cat("    ", paste(rs$out, collapse = "\n    "), "\n", sep = "")
    restart_failed <- c(restart_failed, step[[1]])
  }
}
if (length(restart_failed)) {
  die(6, "RESTART_INCOMPLETE: files are uploaded and verified (backup in ", bdir,
      "), but not done: ", paste(restart_failed, collapse = ", "),
      ". Run them on the server by hand or fix the config (sudo needs to work ",
      "without a password for these commands).")
}
cat("\nUPLOAD_OK: backup in ", bdir, "\n", sep = "")
