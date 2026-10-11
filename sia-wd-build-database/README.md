# sia-wd-build-database

A [Claude Code](https://claude.com/claude-code) skill that builds the Stress in Action Wearables Database (SiA-WD) from the researchers' source "mother tables". Start the skill, answer at most a few short questions, and it checks the inputs, runs the pipeline, verifies the result and reports what was produced and where.

The skill drives the public data pipeline [`sia.project.1.wd.data`](https://github.com/HugoGit39/sia.project.1.wd.data). It does not replace or modify that pipeline.

## What it produces

- The wide table (one row per device).
- The RDS files for the SiA Shiny apps (filter, info, detailed reliability, validity and usability studies, UI constants, glossary, update notes, codebook).
- The OSF export: an Excel workbook (overview sheet plus one sheet per device with detailed studies) and the matching RDS.

The SiA-WD Shiny app is live at https://wearables.stress-in-action.nl and the database exports are on OSF at https://osf.io/umgvp/. The database is described in Schoenmakers et al., *Behavior Research Methods* (2025).

## Who it is for

Researchers who maintain the mother tables. No R knowledge is needed for a normal run: the skill explains each problem in plain language and names the file and column to fix.

## How it works

1. **Locate the repo**, pull the latest version from GitHub, let the researcher update the mother tables in `data/raw/`, and ask one question: all devices, or a selection?
2. **Preflight** (read-only): R and packages, the 7 mother tables (exact names, columns, required values, keys), consistent `device_id`. A failure stops the run.
3. **Same-day check**: warns before a rerun overwrites today's dated outputs.
4. **Run** the repo scripts in the repo's own order (`01` to `04b`, then `05.ui_constants.R`, or `ui_constants.R` in older clones) with progress per step.
5. **Verify** with three deterministic checks:
   - `validate.R`: expected files, row counts, unique keys, expected filter columns, OSF workbook structure, empty columns.
   - `roundtrip.R`: re-reads every source value and compares it with the matching cell in the wide table, the Shiny files and the OSF workbook. Any mismatch fails the run.
   - `release_diff.R`: compares with the previous release and lists devices added or removed and fields changed, for the researcher to confirm.
6. **Reviewer**: one read-only subagent reads only the three reports and flags anything suspicious (implausible values, scores outside 0 to 10, impossible years, unit slips, large jumps, devices with many empty fields). It is a second pair of eyes, not a guarantee. The researcher signs off.
7. **Report**: result, files produced, counts, verification summary, warnings and the next steps.
8. **Commit and push** (full runs only, after a yes): the changed mother tables and the new outputs go to GitHub together.

### Subset mode

Rebuild only some devices with `--devices=a,b` or `--devices-file=path`. The repo scripts stay untouched. All outputs are marked **PARTIAL** and must not be published to Shiny or OSF. The checks compare only the selected devices, and devices outside the selection are never reported as removed.

## Safety

The skill never uploads to OSF, copies files into the app or touches the live app; the app and server part is the skill `sia-wd-deploy-shiny`, OSF stays manual (`references/handoff.md`). Its only git writes are a fast-forward `git pull` at the start and, after an explicit yes, one commit and push of the mother tables and outputs. It never forces, merges or stashes. It needs no credentials and never edits the mother tables or the repo's scripts. It writes only dated files into `data/processed/` and `data/processed/verification/` (older clones also write `df_codebook.rds` in the repo root).

## Install

Copy this folder into a Claude Code skills folder, for example:

```
git clone https://github.com/HugoGit39/sia-wd-skills
cp -r sia-wd-skills/sia-wd-build-database ~/.claude/skills/
```

Then, in a clone of the data pipeline repo, ask Claude Code to "build the SiA database" (other trigger phrases: "run the SiA-WD pipeline", "update mother tables", "generate OSF export", "generate Shiny RDS", "rebuild only some devices").

## Requirements

- Claude Code.
- R (a recent 4.x release), plus the packages the pipeline loads, and `testthat` for the tests. The skill prints the exact `install.packages(...)` line if something is missing.
- A clone of [`sia.project.1.wd.data`](https://github.com/HugoGit39/sia.project.1.wd.data) with the 7 mother tables in `data/raw/`.

## Contents

- `SKILL.md`: the skill (flow, rules, subset mode).
- `scripts/preflight.R`, `run_pipeline.R`, `validate.R`, `roundtrip.R`, `release_diff.R`, `common.R`: the checks and the runner.
- `scripts/tests/test_checks.R`: tests for the shared helpers.
- `references/input_tables.md`: the 7 mother tables, columns and required values.
- `references/handoff.md`: output-to-app mapping and the manual publishing steps.
- `references/reviewer_prompt.md`: prompt for the reviewer subagent.

## Status

Version 0.2. The helper tests pass, and a full run and a two-device subset run were tested on a copy of the pipeline repo. Known open points for the pipeline owners are listed in `SKILL.md`, section "Subset mode". One example: the commented `DEVICE_FILTER` block in script `02` does not cover the detailed reliability, validity and usability table.

## Citation

When you share anything derived from the SiA-WD filters, cite Schoenmakers et al., *Behavior Research Methods* (2025).

## Copyright and licence

Copyright of the Stress in Action materials sits with Stress in Action. The licence of this repository is not yet decided and no licence file is included.
