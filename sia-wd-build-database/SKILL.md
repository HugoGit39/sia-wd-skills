---
name: sia-wd-build-database
description: "This skill should be used when a Stress in Action Wearables Database (SiA-WD) researcher wants to build or rebuild the SiA-WD relational database from the mother tables, update the mother tables and regenerate outputs, build the database for a selection of devices only, generate the Shiny RDS files for the SiA Shiny apps, or generate the OSF export (Excel). Trigger phrases: build the SiA database, run the SiA-WD pipeline, update mother tables, generate OSF export, generate Shiny RDS, refresh the wearables database, rebuild only some devices."
metadata:
  version: "0.3"
  source: "https://github.com/stress-in-action/sia.project.1.wd.data"
---

# SiA-WD: build the database

Run the SiA-WD relational data pipeline (repo `sia.project.1.wd.data`) end to end: check inputs, build, validate, verify, report. Audience is researchers, so use plain language, ask as few questions as possible, and show progress per step.

## Hard limits

- NEVER upload to OSF, copy files into the Shiny app repo, deploy, or touch the live app. Those are explained in the final report (the app and server part is the skill `sia-wd-deploy-shiny`).
- The only git writes: `git pull --ff-only` in step 1, and the commit and push of the data repo in step 9, after an explicit yes. Never merge, rebase, force or stash.
- NEVER edit the mother tables or the repo's R scripts. The researcher edits the mother tables. The pipeline writes only dated files into `data/processed/` (with the older `ui_constants.R` also `df_codebook.rds` in the repo root). The verification steps write only into `data/processed/verification/`.
- Never store or print credentials. The pipeline needs none.

## Flow

### 1. Locate the repo, get the latest version, then the mother tables

Use the current folder if it holds `data/raw/` and `src/application/`. Otherwise look for a folder named `sia.project.1.wd.data` nearby. If none exists, ask once for the path, or offer `git clone https://github.com/stress-in-action/sia.project.1.wd.data` (read-only download, no credentials). Call this folder ROOT.

Find R: `Rscript` on the PATH, otherwise the newest `C:/Program Files/R/R-*/bin/Rscript.exe` (Windows) or `/usr/local/bin/Rscript` (macOS). Use it for every `Rscript` call below. None found: stop, R must be installed.

**Latest version first.** The pipeline reads only the local files in `ROOT/data/raw/` (nothing is downloaded), so the clone must be level with GitHub before anyone edits a table. Run `git -C ROOT fetch`, then `git -C ROOT status -sb`:

- Level with GitHub: continue.
- Behind and no local changes: `git -C ROOT pull --ff-only`.
- Behind and the researcher already changed mother tables locally: stop. Explain that someone else changed the repo in the meantime; their edits must be saved elsewhere, the clone pulled, and the edits redone. Do not stash or merge for them.
- Ahead or diverged: stop and explain.

**Mother tables.** They live in `ROOT/data/raw/` and are tracked by git. Ask: "Did you already update the mother tables in `data/raw/`?" If not, tell the researcher to edit them there now (same file names) and say when done. Newer files kept elsewhere: ask them to place them there (do not copy over existing files without a yes). Show `git -C ROOT status --short data/raw` so the changed tables are visible.

Ask one line: **"All devices, or a selection?"** Default is all devices (full run). For a selection, take either a list of `device_id` values or a text file with one id per line. This is subset mode, see "Subset mode" below. Add the same `--devices=a,b` or `--devices-file=path` option to every script call in steps 2 to 7.

### 2. Preflight (read-only)

Run `Rscript <skill>/scripts/preflight.R ROOT [subset option]`. It checks R, packages, the 7 mother tables (exact file names, columns, required values, keys) and prints PASS / WARN / FAIL. In subset mode it also checks that every requested device_id exists in every mother table and suggests close matches for typos. Details of what is expected: `references/input_tables.md`.

- Missing packages: show the printed `install.packages(...)` line and ask for one yes/no before installing.
- FAIL: stop, explain each failure in plain language, say which file and column to fix. Do not run the pipeline.
- WARN: list them, say what the pipeline will do with them (e.g. duplicates are silently merged), and ask one question: continue or fix first.

### 3. Check for same-day outputs

Outputs carry today's date (`_YYYYMMDD`). If files with today's date already exist in `ROOT/data/processed/`, tell the researcher a rerun overwrites them (earlier dates stay untouched) and ask for a yes before continuing. In subset mode add: a partial run replaces a full set of the same day, so the full set must be rebuilt afterwards.

### 4. Optional: update text for the Shiny app

The UI script (`src/application/05.ui_constants.R`, in older clones `ui_constants.R`; preflight prints which one) holds the app's "Recent updates" text and the glossary. Ask once: "Did you change anything the app homepage changelog or glossary should mention?" If yes, tell them to edit that file themselves and say when done (do not edit it for them). If no, continue.

### 5. Run

Run `Rscript <skill>/scripts/run_pipeline.R ROOT [subset option]` (add `--skip-ui` only if the researcher wants no Shiny UI objects). It sources the repo scripts in the repo's own order and reports each step:

1. `01.sia.p1.packages.R` loads packages
2. `02.sia.p1.read.data.R` reads the 7 mother tables
3. `03.sia.p1.wd.data.wide.R` builds the wide table (one row per device), writes `df_wide_sia_wd_<date>.rds`
4. `04a.sia.p1.wd.data.wide.to.shiny.R` writes the filter, info and detailed-RVU RDS files
5. `04b.sia.p1.wd.data.wide.to.osf.R` writes the OSF Excel workbook and the OSF RDS
6. `05.ui_constants.R` (or the older `ui_constants.R`, detected automatically) writes `ui_constants`, `glos`, `updates` RDS and the codebook (`data/processed/df_codebook_<date>.rds`, or `df_codebook.rds` in the root with the older script)

It also writes `data/processed/run_mode_<date>.txt` (FULL or PARTIAL plus the device list), which the checks below read by themselves.

Run everything in one go: 04a and 04b look for the wide file dated today, so a run that crosses midnight breaks.

On error: show the failing step and message in plain language, suggest the likely cause from the input checks, do not retry blindly.

### 6. Verify (three deterministic checks)

Run these three, keep each output text, and do not stop after the first problem:

1. `Rscript <skill>/scripts/validate.R ROOT`: expected files exist, row counts equal the number of devices, device_id unique, filter plus info columns cover the wide table, expected filter columns exist, OSF workbook sheets, empty OSF columns. It ends with plain facts (score range, year range, min/median/max per numeric field, devices with many empty fields) for the reviewer.
2. `Rscript <skill>/scripts/roundtrip.R ROOT`: re-reads every mother-table value and compares it with the matching cell in the wide RDS, the Shiny filter, info and detailed-RVU files, the OSF RDS and the OSF workbook (overview and device sheets), with the same empty-value tokens as the pipeline. Renamed or aggregated columns are compared through their documented transformation; columns it cannot map are listed as skipped, never guessed. Exit status 1 on any mismatch. Writes `verification/roundtrip_summary_<date>.txt` and `roundtrip_mismatches_<date>.csv`.
3. `Rscript <skill>/scripts/release_diff.R ROOT [--prev=<YYYYMMDD or folder>]`: compares with the previous release (newest earlier full set in `data/processed/`, or the one the researcher names). Lists devices added and removed and, per device, the fields that changed (old value, new value), by table. Writes `verification/release_diff_<date>.txt` and `.csv`. It never fails the run; the researcher confirms the changes are intended. With no previous release it says so and skips.

A validate FAIL or a roundtrip mismatch means the outputs are not trustworthy: explain in plain language (which table, device and column) and stop before the reviewer step.

### 7. Reviewer (second pair of eyes)

After validate, roundtrip and diff, spawn ONE subagent with the Agent tool (type `Explore`, which has no write tools). Use the prompt in `references/reviewer_prompt.md` and paste in only three things: the validate output, the roundtrip summary, the release diff report (or "no previous release"). The reviewer reads nothing else, runs nothing, and changes nothing.

It returns a short list ranked by seriousness, each item with device_id, field and why it looks wrong (implausible values, scores outside 0 to 10, impossible dates or years in the future, unit slips such as hours vs minutes, large jumps against the previous release, devices with many empty fields).

State this plainly to the researcher: **the reviewer is a second pair of eyes, not a guarantee.** It only sees the three reports, so it can miss problems that do not show up there. The researcher signs off.

### 8. Report

Finish with a short summary:

- **Result**: passed or what failed. For a subset run, start with: "PARTIAL: only N devices, not for publication to Shiny or OSF."
- **Produced** (full paths in `ROOT/data/processed/`): Shiny files (`df_shiny_sia_wd_filter`, `df_shiny_sia_wd_info`, `df_shiny_rvu_detailed`, `df_osf_sia_wd_shiny`, plus `ui_constants`, `glos`, `updates`, and the codebook), the OSF workbook `df_osf_sia_wd_<date>.xlsx`, the intermediate `df_wide_sia_wd_<date>.rds`, and the verification reports in `data/processed/verification/` (files of a subset run end in `_partial`).
- **Counts**: devices, columns per table, workbook sheets, roundtrip cells checked.
- **Verification**: roundtrip result, number of changes against the previous release, the reviewer's list (top items).
- **Warnings** carried over from preflight and validation.
- **Sign-off**: ask the researcher to confirm the diff changes and the reviewer items are understood.
- **Next steps**: step 9 below, then `references/handoff.md`. For a subset run `handoff.md` says: do not publish.

### 9. Commit and push the data repo (full runs only)

The mother tables and the outputs are released together: researchers and the deploy skill work from what is on GitHub. Only after the sign-off in step 8, and never for a PARTIAL run:

1. Show `git -C ROOT status --short`. Mark what will be committed: the changed files in `data/raw/`, the files with today's date in `data/processed/` and `data/processed/verification/`, and the root `df_codebook.rds` if the older script wrote it. Anything else changed (R scripts, README) is listed and left alone.
2. Ask: **"Commit and push the mother tables and outputs to GitHub? yes / no"**.
3. On yes: `git add` exactly those paths, commit `Update SiA-WD data <date>`, `git push` with the researcher's own GitHub login. Show the commit hash. A rejected push (someone pushed in the meantime): stop, never force, explain.
4. On no: say the build stays local only, and that the deploy skill and other researchers will not see it until it is pushed.

## Subset mode

The researcher names devices; the repo scripts stay untouched. `run_pipeline.R` sources the repo scripts one by one and, right after the read step (02), applies the same filter the commented `DEVICE_FILTER` block in script 02 would apply, to all seven tables, then continues with 03 to 06. Chosen over editing a copy of the scripts because it needs no change to the repo, uses the very objects the later scripts read, and cannot be forgotten in a script update.

Open question for the repo owners: the commented block leaves out `rvu_detailed`, so enabling it as written would still write every device's studies into the Shiny detailed-RVU file and the OSF device sheets. The wrapper filters `rvu_detailed` too.

Rules:

- Preflight: every requested device_id must exist in the mother tables (FAIL if missing from `devices` or `expert_scores`, WARN for the others, whose columns would stay empty).
- Roundtrip compares only the selected devices.
- Release diff compares the selected devices with the same devices in the previous release. Devices outside the selection are never reported as removed. A partial set is never used as a previous release.
- Everything a subset run produces is PARTIAL: banner in the reports, `_partial` in the verification file names, `run_mode_<date>.txt` says PARTIAL, and the final report and hand-off say it is not for publication to Shiny or OSF. A later full run the same day overwrites the partial files.

## Resources

- `scripts/preflight.R`, `scripts/run_pipeline.R`, `scripts/validate.R`, `scripts/roundtrip.R`, `scripts/release_diff.R`: all take the repo root as first argument; all except run_pipeline are read-only on inputs. `scripts/common.R` holds shared helpers.
- `scripts/tests/test_checks.R`: tests for the helpers (`Rscript -e 'testthat::test_file("scripts/tests/test_checks.R")'`, run from the skill folder's `scripts/tests`).
- `references/input_tables.md`: the 7 mother tables, columns, required values.
- `references/handoff.md`: output-to-app file mapping and the next steps after the push.
- `references/reviewer_prompt.md`: prompt for the reviewer subagent.
