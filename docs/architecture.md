# WinTweak Utility v3.0 — Architecture

## Overview

WinTweak Utility v3.0 is a modular, JSON-driven Windows system optimizer inspired by Chris Titus Tech's WinUtil, with deep gaming hardware control from WinTweak CLI v2.2.

## Layer Diagram

```
┌─────────────────────────────────────────┐
│  UI Layer (WPF XAML)                    │
│  xaml/MainWindow.xaml                   │
│  Dynamically renders from JSON configs  │
├─────────────────────────────────────────┤
│  Logic Layer (PowerShell Functions)     │
│  functions/private/*.ps1 (helpers)      │
│  functions/public/Invoke-WTU*.ps1       │
├─────────────────────────────────────────┤
│  System Operations Layer                │
│  modules/*.psm1                         │
│  GPU, timer, network, power, memory...  │
├─────────────────────────────────────────┤
│  Config Layer (JSON)                    │
│  config/applications.json              │
│  config/tweaks.json                    │
│  config/gaming.json   ← centerpiece    │
│  config/features.json                  │
│  config/repairs.json                   │
│  config/dns.json                       │
│  config/presets.json                   │
└─────────────────────────────────────────┘
```

## Build System

- **Development**: Edit modular files in `functions/`, `modules/`, `config/`, `xaml/`
- **Production**: Run `.\Compile.ps1` → generates `WinTweakUtility.ps1`
- **Launch**: Run `.\Compile.ps1 -Run` to build and launch
- **Validate only**: Run `.\Compile.ps1 -Validate`

## Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Public functions | `Verb-WTUNoun` | `Invoke-WTUTweak` |
| Private helpers | `Verb-WTUNoun` | `Test-WTUAdmin` |
| Gaming functions | `Verb-WTFNoun` (legacy) | `Invoke-WTFGPUControl` |
| Config keys (Gaming) | `WTU` prefix | `WTFModeCompetitiveStable` |
| Config keys (UI) | `WPF` prefix | `WPFInstallChrome` |

## Logging

Logs stored at: `%LOCALAPPDATA%\WinTweakUtility\Logs\YYYYMM.jsonl`

Format:
```json
{"timestamp":"2026-04-22T18:00:00Z","action":"GamingMode","tweak":"WTFModeCompetitiveStable","user":"SIMO","before":"pre-execution","after":"Apply","success":true,"error":""}
```

## Checkpoint Storage

Checkpoints stored at: `%LOCALAPPDATA%\WinTweakUtility\Checkpoints\`

Each checkpoint directory contains:
- `meta.json` — name, timestamp, user
- `*.reg` — registry snapshots of key paths
- `powerplan.txt` — active power plan GUID
- `gpu_state.txt` — NVIDIA GPU state (if available)
