# DriverDrop

A free, open-source driver updater for Windows. No ads, no "pay to unlock", no bundled junk — just a clean GUI over Windows Update that lets **you** pick exactly which drivers (or updates) to install, with an optional system restore point first.

Everything is one readable PowerShell file. Read it before you run it — that's the whole point of open source.

## Quick start

Open **any** PowerShell window (it will ask for admin by itself) and run:

```powershell
irm "https://raw.githubusercontent.com/YOURUSER/YOURREPO/main/DriverDrop.ps1" | iex
```

Or download `DriverDrop.ps1` and run it locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\DriverDrop.ps1
```

## What it does

- Scans **Microsoft Update** for driver updates (or all Windows updates — your choice)
- Shows everything it found in a list with checkboxes: title, type, KB number, size
- Optionally creates a **system restore point** before touching anything (on by default)
- Installs only what you ticked, streaming progress into a live log
- Tells you if a reboot is needed and offers to do it — never reboots on its own

## Screenshot

*(add a screenshot here after your first run — press `Win + Shift + S`)*

## How it works

Under the hood it uses the well-known [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) module (installed automatically on first run) and the Windows Update Agent — the same machinery Windows itself uses. Nothing is downloaded from anywhere except Microsoft's own update servers.

The restore point is created through the standard `SystemRestore` WMI class, and the script temporarily lifts Windows' "one restore point per 24 hours" limit so the backup actually gets made.

## Requirements

- Windows 10 or 11
- Administrator rights (the script self-elevates via UAC)
- Internet connection

## Good to know

- **Drivers come from Microsoft Update.** These are WHQL-signed and safe, but GPU vendors (NVIDIA/AMD/Intel) and laptop makers often publish newer drivers on their own sites first. For a gaming GPU you may still want the vendor's tool.
- **SmartScreen / antivirus may warn** about running scripts from the internet. That's normal for any `irm | iex` tool (winutil gets the same). Review the script, then decide.
- **Restore point needs System Restore enabled.** The script tries to enable it on your system drive, but if group policy blocks it, it logs a warning and continues.

## Disclaimer

This tool installs updates published by Microsoft, but it's still your machine and your call. Provided as-is, no warranty — see [LICENSE](LICENSE).

## License

MIT — do whatever you want, just keep the notice.
