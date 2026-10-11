# What to check in each app

Use this for the test app, the production app, the siawd package and the live app after upload. Each check takes under a minute.

1. **App boots** without an error screen or a blank page. In the console, no error about a missing `.rds` file.
2. **Product Filter**: the Manufacturer dropdown is populated. An empty dropdown means `data/*.rds` did not load.
3. **Device count**: the number of devices in the app matches the device count in the build report.
4. **A new or changed device**: pick one device from the release diff and compare a few fields with the mother tables.
5. **Comparison table and detailed studies** open for that device.
6. **Homepage**: the "Recent updates" text shows the new entry, and the glossary opens.
7. **Filters**: set two or three filters. Results narrow and reset cleanly.

Any failure at the test app or production app: stop, do not continue to the next gate.
