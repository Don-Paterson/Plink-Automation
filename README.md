# Plink-Automation

A PowerShell GUI tool for running Check Point `clish` commands across multiple Gaia hosts simultaneously via PuTTY's `plink.exe`. Designed for use in [Skillable](https://www.skillable.com/) lab environments running Check Point R82.

## Quick Start

```powershell
irm https://raw.githubusercontent.com/Don-Paterson/Plink-Automation/main/run-plink-automation.ps1 | iex
```

This downloads and launches the GUI directly — no installation required.

## Overview

The GUI lets you select one or more hosts and one or more `clish` commands, then fires them all off in sequence over SSH. Each host gets a single connection; commands are piped via stdin, which is the correct pattern for Check Point's `clish` login shell.

Useful for post-boot lab setup tasks such as unlocking the database, setting shell preferences, adjusting inactivity timeouts, and saving config — all without logging into each host individually.

## Lab Topology

Default hosts match the standard R82 lab layout:

| Host | IP |
|---|---|
| A-SMS | 10.1.1.101 |
| A-GW | 10.1.1.1 |
| A-GW-01 | 10.1.1.2 |
| A-GW-02 | 10.1.1.3 |
| A-SMS-02 | 10.1.1.111 |
| A-Skyline | 10.1.1.130 |

## Features

- Check/uncheck individual hosts and commands before running
- Select All / Select None buttons for both lists
- Add ad-hoc commands at runtime via the text box — they're checked automatically
- Password field (masked); leave blank to fall back to SSH keys
- Non-blocking UI — runs on a `BackgroundWorker` so the window stays responsive
- Auto-scrolling output panel (Consolas, dark background)
- Per-host log files written to `.\logs\<host>.log` relative to the script location
- Exit code captured and shown (`OK` / `EXIT n`) per host
- Password redacted in the display output
- Host keys auto-accepted via `-auto-store-sshkey` (PuTTY ≥ 0.77)

## Requirements

- Windows (PowerShell 5.1 or PowerShell 7)
- [PuTTY](https://www.putty.org/) installed at `C:\Program Files\PuTTY\plink.exe`
- Network access to target Gaia hosts on port 22

## Configuration

Edit the `CONFIG` block near the top of `Automation-Commands-Plink.ps1`:

```powershell
$Hosts           = @('10.1.1.101', '10.1.1.1', ...)   # hosts shown in the list
$Commands        = @('lock database override', ...)    # commands pre-loaded in the list
$User            = 'admin'
$DefaultPassword = 'Chkp!234'                          # pre-fills the password box
$PlinkPath       = 'C:\Program Files\PuTTY\plink.exe'
```

## How It Works

Check Point's SSH login shell is `clish` itself, so there is no need to prefix commands with `clish`. Commands are joined with newlines and piped into `plink` via stdin — equivalent to an interactive clish session:

```
"lock database override`nset inactivity-timeout 720`nsave config" | plink -batch -pw ... admin@10.1.1.101
```

This avoids the `CLINFR0329 Invalid command` error that occurs when `clish` is invoked as a sub-command of itself.

## Files

| File | Purpose |
|---|---|
| `run-plink-automation.ps1` | `irm \| iex` entry point — downloads and runs the main script |
| `Automation-Commands-Plink.ps1` | Main GUI script |

## Related Repos

- [SkillableMods](https://github.com/Don-Paterson/SkillableMods) — UK locale/timezone setup for Skillable lab VMs
- [MobaXterm-Setup](https://github.com/Don-Paterson/MobaXterm-Setup) — Silent MobaXterm install and session injection
- [chkp-monitor](https://github.com/Don-Paterson/chkp-monitor) — Flask health dashboard for Check Point lab gateways
