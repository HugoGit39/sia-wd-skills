# Hand-off: steps after a successful run

The build skill commits and pushes the data repo itself (step 9, after a yes). Everything below that is explained, never performed: the Shiny app and server steps are done by the separate skill `sia-wd-deploy-shiny`, OSF stays manual.

## Subset (PARTIAL) runs: do not publish

If `data/processed/run_mode_<date>.txt` says `mode=PARTIAL`, the outputs hold only the selected devices. They are NOT for publication: do not copy them into the Shiny app, do not upload them to OSF, do not commit them as the release. Rebuild with all devices first. Say this in the final report instead of the steps below.

## Before publishing: sign-off

Read `data/processed/verification/`: the roundtrip summary must show zero mismatches, the release diff lists changes you must recognise as intended, and the reviewer list is a second pair of eyes, not a guarantee. The researcher signs off.

## What the Shiny app reads

From `stress-in-action/sia.project.1.wd.shiny`, `production/app/global.R` (and `test/app/global.R`) read these files WITHOUT the date suffix:

| App reads | Pipeline produced |
|---|---|
| `data/df_shiny_sia_wd_filter.rds` | `df_shiny_sia_wd_filter_<date>.rds` |
| `data/df_shiny_sia_wd_info.rds` | `df_shiny_sia_wd_info_<date>.rds` |
| `data/df_shiny_rvu_detailed.rds` | `df_shiny_rvu_detailed<date>.rds` (no underscore before the date) |
| `data/df_osf_sia_wd_shiny.rds` | `df_osf_sia_wd_shiny_<date>.rds` |
| `www/ui_constants.rds` | `ui_constants_<date>.rds` |
| `www/glos.rds` | `glos_<date>.rds` |
| `www/df_codebook.rds` | `df_codebook_<date>.rds` in `data/processed/` (older `ui_constants.R`: `df_codebook.rds` in the repo root) |
| `www/updates.rds` | `updates_<date>.rds` |

The names must be renamed (date dropped) and copied into the app's `data/` and `www/` folders (in siawd: `inst/app/data/` and `inst/app/www/`). The skill `sia-wd-deploy-shiny` does this and checks every copy by checksum.

## Next steps (suggest, do not do)

1. **Data repo (required)**: the changed mother tables and the new outputs must be committed and pushed together. The build skill does this in step 9 after a yes; if the researcher said no there, they must do it by hand before deploying, with their own GitHub login.
2. **Shiny app and server**: after a full, signed-off build, run the skill `sia-wd-deploy-shiny`. It copies the renamed files into `test/app`, runs the app locally for a check, repeats that for `production/app` and for the siawd golem package (`inst/app`), commits and pushes both repos (siawd with a version bump and tag), and on request uploads the production files to the live Shiny server over SSH (VU network or VPN and an SSH key needed). The live app runs on a Shiny Server at Vrije Universiteit Amsterdam.
3. **OSF**: upload `df_osf_sia_wd_<date>.xlsx` (and any other files the team publishes) to the OSF project https://osf.io/umgvp/ through the OSF web interface.

Remind that re-running on the same day overwrites that day's outputs, and that older dated files in `data/processed/` are kept.
