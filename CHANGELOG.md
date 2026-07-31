# Changelog

All notable changes to DriverDrop are documented here, newest first.
You can also see this inside the app - click the version badge in the title bar.

## [1.4.1] - 2026-07-31

### Changed
- Two-branch workflow: `prod` is the stable branch everyone runs from; `staging` is ongoing development
- The public one-liner and the script's self-elevation URL now point at `prod` (in both branches, so merges need no edits)
- README documents both branches and the dev one-liner

## [1.4.0] - 2026-07-31

### Added
- In-app changelog: the version badge in the title bar is now clickable and opens a "What is new" panel with the full version history
- This CHANGELOG.md file, so changes are tracked in the repo too
- Esc or clicking outside the panel closes the changelog

## [1.3.0] - 2026-07-31

### Changed
- History is now human readable: raw driver titles like `INTEL - System - 10/3/2016 12:00:00 AM - 10.1.1.38` are parsed into clean names like `INTEL System driver 10.1.1.38 (driver from 2016-10-03)`
- History entries are grouped by day with headers (Today / Yesterday / date) and per-day counts
- Duplicate entries on the same day are collapsed into one row with an `(x2)`, `(x3)` suffix
- Store app IDs like `9NRZT3Q9R3DL-...` are stripped down to the actual app name
- The Action column was replaced by category pills showing the driver class (System, LAN, Bluetooth, ...), Store app, Defender, or Update
- Uninstalls now show as an amber `Removed` pill instead of a green `Succeeded`
- Fake pre-1990 driver dates (Intel's 1968 ranking trick) are hidden from titles
- The filter box also matches history categories

## [1.2.0] - 2026-07-31

### Added
- `Released` column: the manufacturer's driver date for drivers (the same date Device Manager shows), or the publish date for regular updates
- `Device` column: the friendly hardware name the driver targets
- Details pane: click a row to see the device, manufacturer, driver date, KB, size and Microsoft's description
- History view (`Available` / `History` switcher) showing everything Windows Update has installed, newest first, with result pills
- History loads automatically on first open, has a refresh button, and reloads after installs

### Changed
- The filter box also matches device names

## [1.1.0] - 2026-07-31

### Added
- Custom dark title bar with app icon, version badge and min / max / close buttons
- Segmented controls for scan scope and a toggle switch for the restore point option
- Type badges (Driver / Software), a live filter box, and friendly empty states
- Live selected count on the Install button; it disables when nothing is ticked
- Double-click a row or press Space to toggle; Select all respects the active filter
- Slim dark scrollbars, row hover highlight, a thin busy indicator, and a Clear log button

### Fixed
- Removed the dotted focus rectangle that appeared on grid cells

## [1.0.0] - 2026-07-31

### Added
- First release: a dark WPF GUI over Windows Update in one self-contained `.ps1`
- Scan Microsoft Update for drivers only or all updates, then tick exactly what to install
- Optional system restore point before installing (the 24-hour limit is lifted automatically)
- Reboot prompt when required - never reboots on its own
- Self-elevation via UAC and automatic install of the PSWindowsUpdate module on first run
- Runs straight from GitHub with the `irm | iex` one-liner
