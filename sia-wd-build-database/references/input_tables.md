# Mother tables (ROOT/data/raw/)

Source: repo README and `src/application/02`, `03`, `04a`, `04b`. File names must match exactly (xlsx, first sheet is read). Column names are cleaned with `janitor::clean_names()` on read, so `Device ID` and `device_id` both work.

**Empty values:** these cell values are read as missing: empty, `NA`, `NP`, `N/A`, `Na`, `na`, `NULL`, `-9999`.

**Key:** `device_id` (text, e.g. `001_sia_wd_emp`). One row per device in `devices.xlsx`; the other tables repeat it (long format). `device_id` must be spelled identically in every file.

| File | Shape | Columns |
|---|---|---|
| `devices.xlsx` | 1 row per device | device_id, manufacturer, model, website, release_year, market_status, main_use, device_cost, device_cost_info, wearable_type, location, size_mm, weight_gr |
| `signals.xlsx` | long: device x signal | device_id, signal_name, available, sampling_rate_min, sampling_rate_max, additional_info, recording_location |
| `technical_specs.xlsx` | long: device x spec | device_id, spec_name, spec_boel_value, spec_num_value, spec_num_unit, spec_char_value |
| `data_access.xlsx` | long: device x spec | same six columns as technical_specs |
| `rvu_synthesis.xlsx` | long: device x synthesis type | device_id, synthesis_type, n_of_studies, evidence_level, parameters_studied, synthesis, date_of_last_search |
| `expert_scores.xlsx` | long: device x score type x reviewer | device_id, score_type, score_by, score |
| `rvu_synthesis_detailed.xlsx` | one row per study | device_id, study_citation, year, journal, external_internal, population, sample_size, age, reference_device, reference_device_other, events, events_included, param_studied, test_retest_time, conclusion_authors, sum_val_rel, sum_usability, final_verdict (the scripts need device_id and year; the rest passes through to the per-device OSF sheets) |

## Values the scripts refer to by name

Labels are normalised (lowercase, non-alphanumerics become `_`), so `Short-term` and `short_term` are the same.

- `signal_name`: ppg, ecg, icg, emg, respiration, eda, eeg, bp, accelerometer, gyroscope, gps, skin_temperature, other_signals
- `technical_specs` `spec_name`: water_resistance, battery_life, charging_method, charging_duration, bio_cueing, bio_feedback
- `data_access` `spec_name`: raw_data_available, parameters_available, parameters_resolution, data_transfer_method, windows_compatible, macos_compatible, android_compatible, ios_compatible, software_required, software_additional, int_storage_met, server_data_storage, dev_storage_cap_hr, dev_storage_cap_mb, gdpr_compliance, fda_clearance, ce_marking
- `synthesis_type`: reliability and validity, usability
- `score_type`: short-term, long-term; `score_by` must include `all` (the app uses the `all` score)

## Behaviour worth telling researchers

- The wide table starts from `expert_scores.xlsx`: a device without score rows is dropped from every output.
- Duplicate device/key rows are merged silently: first non-empty text, maximum for numbers (sampling_rate_min uses the minimum, scores use the mean).
- Non-numeric entries in numeric columns (sampling rates, spec_num_value, n_of_studies, score) become empty.
- `available`, `spec_boel_value` are read as yes/no style values (yes, y, true, t, 1 become 1; no, n, false, f, 0 become 0; anything else is empty) when OSF cells are built.
- Per-device OSF sheet names are the first 31 characters of device_id.
- `data/raw/` in the repo currently holds 45 devices; the commented `DEVICE_FILTER` in script 02 can restrict a run to chosen devices but is not active, and it skips `rvu_detailed` (looks like a gap). The skill's subset mode (`--devices` / `--devices-file` on the scripts) applies the filter from the wrapper, including `rvu_detailed`, without editing the repo. Only use it when the researcher asks for a selection.
