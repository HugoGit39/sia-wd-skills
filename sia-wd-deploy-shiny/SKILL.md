---
name: sia-wd-deploy-shiny
description: "This skill should be used when a Stress in Action Wearables Database (SiA-WD) researcher has a finished, verified full build of the Shiny RDS files and wants to put them into the SiA apps: test them in the test app locally, move them into the production app and test again, update and test the siawd golem package, commit and push both repos (with a siawd version bump and tag), and upload the files to the live Shiny server over SSH. Trigger phrases: deploy the SiA database to the app, update the Shiny app with the new RDS files, update the siawd package data, test the new data in the app, push the new data to the server, upload RDS to the server, publish the SiA app update."
metadata:
  version: "0.3"
  source: "https://github.com/stress-in-action/sia.project.1.wd.shiny"
---

project: [[phd_postdoc]]

# SiA-WD: deploy to the Shiny apps

Take the RDS files from a finished `sia-wd-build-database` run and carry them through five gates: test app (local), production app (local), siawd package (local), GitHub, live server (SSH). Audience is researchers, so use plain language, ask as few questions as possible, and stop at the first gate that fails.

Three repos are involved:

- DATA = `sia.project.1.wd.data` (holds `data/processed/`).
- APP = `sia.project.1.wd.shiny` (holds `test/app/` and `production/app/`). `test/app` is local only. `production/app` is exactly what runs on the server.
- SIAWD = `siawd`, the golem package version of the app (holds `inst/app/data/` and `inst/app/www/`). It reads the files through `system.file()`, so a local test must use `pkgload::load_all()`, never the installed package.

## Hard limits

- Touch only the 8 data files per app folder (4 in `data/`, 4 in `www/`, listed in `scripts/deploy_common.R`), plus the `Version:` line of SIAWD's `DESCRIPTION` through `scripts/bump_siawd_version.R`. NEVER edit `global.R`, `app.R`, modules, functions or any R code, and NEVER copy `global.R` between `test` and `production` (they differ by design).
- NEVER read or print `.Renviron` files.
- NEVER skip a gate. Production staging only after the test app was confirmed. SIAWD only after production was confirmed. Commit and push only after every staged app was confirmed. Upload only after the commit step was answered.
- Commit only the staged paths (16 in APP; 8 plus `DESCRIPTION` in SIAWD), push without force, to the branch the researcher is on. Ask for an explicit yes first. Use the researcher's own GitHub login.
- Upload goes to production only. Ask the upload question exactly once and never upload without a yes. Never delete anything on the server. The backup is a copy. On the server run only the two configured commands (Shiny Server restart, nginx reload), nothing else.
- Never store or print passwords, keys or tokens. SSH uses the researcher's own key. Host, user and paths live only in `~/.sia_wd_deploy.conf`, outside every repo.
- Never deploy a PARTIAL run. Never touch OSF.
- Remind the researcher that anything shared from the app's filters must cite Schoenmakers et al., Behav Res Methods 2025.

## Flow

### 1. Preconditions (read-only)

- Locate DATA, APP and SIAWD (current folder or nearby folders with those names; ask once for a path if missing). No SIAWD clone: ask once whether to skip the siawd gate. A skipped gate is reported as skipped.
- Pick the dated set: default is the newest FULL set in `DATA/data/processed/` (`newest_ds()` skips PARTIAL sets). State the date.
- `data/processed/run_mode_<date>.txt` must say `mode=FULL`. PARTIAL: stop, rebuild with all devices first.
- Read `data/processed/verification/roundtrip_summary_<date>.txt`: zero mismatches required. Otherwise stop.
- Ask for the sign-off: "Did you confirm the release diff and the reviewer items from the build?" Needs a yes.
- **Find R.** Use `Rscript` if it is on the PATH, otherwise the newest `C:/Program Files/R/R-*/bin/Rscript.exe` (Windows) or `/usr/local/bin/Rscript` (macOS). Call it RSCRIPT and use it for every `Rscript` call below. None found: stop and say R must be installed.
- **Latest code from GitHub.** The local tests run the code in the local clones, so first bring them level with GitHub. For APP and SIAWD: `git fetch`, then `git status -sb`.
  - Behind: `git pull --ff-only`. Diverged, or the pull refuses: stop and explain. Never merge, rebase or force.
  - Uncommitted changes in any of the 8 data paths: stop, they would be overwritten.
  - Other uncommitted changes (for example README, R code): list them and continue. Say plainly that the test then includes those local changes, which GitHub does not have. They are never committed by this skill.
  - Report per repo: branch, commit hash, "matches GitHub" or what differs.
- **Packages.** `RSCRIPT <skill>/scripts/check_packages.R APP SIAWD` (leave out SIAWD when that gate is skipped). It reads the package lists from both `global.R` files and the siawd DESCRIPTION. Missing packages: show the printed install line, ask one yes/no, then rerun with `--install`. Do not start any app while packages are missing.

### 2. Gate 1: test app, local

1. `RSCRIPT <skill>/scripts/stage_files.R DATA APP test <date>` copies the 8 files into `APP/test/app/`, renamed without the date, and checks every copy by checksum.
2. Start the app as a background process: `RSCRIPT -e "shiny::runApp('<APP>/test/app', port = 7311, launch.browser = TRUE)"`. Write `<APP>` as an absolute path with forward slashes (`C:/Users/...`): a backslash breaks the R string. Shiny opens the app in the default browser as soon as it is ready. Also poll `http://127.0.0.1:7311` until it answers 200, to confirm; no answer after 60 seconds: show the app's console output and stop. If the browser did not open, give the researcher the URL.
3. Tell the researcher to run `references/app_checks.md` in that browser tab. Ask one line: **"Test app OK? yes / no"**.
4. Stop the app: stop the background process, then check that port 7311 no longer answers. Still answering (on Windows the R child process can survive): find the process listening on the port (`netstat -ano | findstr :7311`) and end that one process (`taskkill /PID <pid> /F`). `no`: stop the whole flow, ask what looked wrong.

### 3. Gate 2: production app, local

1. `RSCRIPT <skill>/scripts/stage_files.R DATA APP production <date>`. It also warns if the 8 files in `test/app` and `production/app` differ.
2. Start `<APP>/production/app` the same way on port 7312; it opens in the browser too. Same checks. Ask: **"Production app OK? yes / no"**. Stop the app the same way afterwards.

### 4. Gate 3: siawd package, local

1. `RSCRIPT <skill>/scripts/stage_files.R DATA SIAWD siawd <date>` copies the same 8 files into `SIAWD/inst/app/`.
2. Start it as a background process with SIAWD as the working directory: `RSCRIPT -e "pkgload::load_all('.'); siawd::run_app(options = list(port = 7313, launch.browser = TRUE))"`. It opens in the browser. Poll `http://127.0.0.1:7313` as above.
3. Same checks. Ask: **"siawd OK? yes / no"**. Stop the app the same way afterwards.

### 5. Gate 4: version bump, commit and push

1. `RSCRIPT <skill>/scripts/bump_siawd_version.R SIAWD --dry-run` gives the old and new version (patch bump, for example 1.0.0 to 1.0.1). A version that is not plain x.y.z: ask before changing it.
2. Show `git status --short` and `git diff --stat` for APP and SIAWD. Mark which paths will be committed (the staged data paths, plus `DESCRIPTION` in SIAWD) and which other changed files stay uncommitted.
3. Ask once: **"Commit and push APP, and siawd as v<new> with tag? yes / no"**. On yes:
   - APP: `git add` the 16 paths, commit `Update SiA-WD data <date>`, `git push`.
   - SIAWD: run `bump_siawd_version.R SIAWD` (no dry run), `git add` the 8 paths and `DESCRIPTION`, commit `Update SiA-WD data <date>, v<new>`, `git tag v<new>`, `git push`, then `git push origin v<new>`.
   - Show the commit hashes. A rejected push (remote has new commits): stop, do not force, tell the researcher to pull first. An existing tag: stop and ask.
4. On no: nothing is committed, pushed, tagged or bumped; the staged files stay in the local clones. Then ask whether to go on to the server upload anyway, and say that the server would then run data that GitHub does not have. No: finish with the report.

### 6. Gate 5: upload to the server

Ask the final question: **"Upload to the server? yes / no"**. On no, finish with the report.

On yes:

1. If `~/.sia_wd_deploy.conf` is missing, create it from `references/server_config.template.txt`. Ask the researcher for each value (host, user, remote app folder, optional port and key, the Shiny Server restart command, the nginx reload command). If they do not know the remote app folder or either command, point to `references/ssh_setup.md` and stop.
2. `RSCRIPT <skill>/scripts/upload_to_server.R APP --check`. It tests the SSH login without any prompt, the server folder layout and the write rights. Nothing is changed.
   - Exit 2 (SSH fails): print the matching advice from `references/ssh_setup.md` (VPN or VU network first, then key setup), stop.
   - Exit 3 (folder wrong): ask for the right remote app folder, update the config, repeat.
   - Exit 7 (no write rights): stop, tell the researcher to ask the server admin for write rights on the app folder and its `data/` and `www/`.
3. `RSCRIPT <skill>/scripts/upload_to_server.R APP --upload`. It backs up the 8 existing remote files into `<remote app folder>/_backup_<timestamp>/` (stops if the backup fails), copies the 8 files from `production/app` with scp, compares checksums local against remote, then restarts Shiny Server and reloads nginx with the two commands from the config, in that order. Restarting drops open visitor sessions, so suggest a quiet moment. Exit 6 means the files are on the server and verified but a restart or reload failed or is not configured: show which one and let the researcher fix the config or run it by hand.
4. Open the live app `https://wearables.stress-in-action.nl/` and ask the researcher to repeat the first checks in `references/app_checks.md`. Any problem: restore from the `_backup_<timestamp>` folder (show the copy commands, do not run them without a yes).

### 7. Report

- **Result** per gate: test, production, siawd, GitHub, server (done / skipped / failed).
- **Date** of the data set, **commit hashes**, **siawd version and tag**, **backup folder** on the server.
- **Warnings** carried over.
- **Citation reminder.**

## Resources

- `scripts/deploy_common.R`: file list, folders per target, name mapping, run-mode reader, checksum helper.
- `scripts/check_packages.R`: missing R packages for both apps and siawd, `--install` after a yes.
- `scripts/stage_files.R`: copy, rename and verify into `test`, `production` or `siawd`.
- `scripts/bump_siawd_version.R`: patch bump of the siawd `Version:` line, `--dry-run` to preview.
- `scripts/upload_to_server.R`: `--check` and `--upload`.
- `references/server_config.template.txt`: the config the researcher fills in.
- `references/ssh_setup.md`: VPN, key setup, finding the remote folder, the restart and reload commands, sudo without password.
- `references/app_checks.md`: what to look at in each app.
