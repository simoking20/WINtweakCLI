#Requires -Version 5.1
<#
.SYNOPSIS  WinTweak Utility v3.0 - Main WPF Entry Point
.DESCRIPTION
    Bootstraps the WPF UI: loads WPF assemblies first, then validates admin,
    loads all configs, wires all events, and shows the window.
    Called by Compile.ps1 as the final block in the compiled output.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\main.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# â"-"€ 1. Load WPF assemblies FIRST (MessageBox needs PresentationFramework) â"€â"€
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# â"-"€ 2. Admin check â"-"€
try {
    Test-WTUAdmin
} catch {
    [System.Windows.MessageBox]::Show(
        $_.Exception.Message,
        "WinTweak Utility - Admin Required",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Warning
    ) | Out-Null
    exit 1
}

# â"-"€ 3. Determine root path (compiled = single file, dev = scripts\ parent) â"-"€
$Root = if ($PSScriptRoot) {
    # Dev mode: this file is in scripts\, root is one level up
    Split-Path $PSScriptRoot -Parent
} else {
    # Compiled mode: $PSScriptRoot is empty for inline script blocks
    Split-Path $PSCommandPath -Parent
}

# â"€â"€ 4. Load and validate all JSON configs â"€â"€
$configs     = @{}
$configNames = @('applications','tweaks','gaming','features','repairs','dns','presets')

# Compiled mode: configs are already in $sync.configs (set by Compile.ps1 output)
# Dev mode: load from disk
if (-not (Get-Variable 'sync' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:sync = @{ configs = @{} }
    foreach ($name in $configNames) {
        $path = Join-Path $Root "config\$name.json"
        if (Test-Path $path) {
            try {
                $global:sync.configs[$name] = Get-Content $path -Raw | ConvertFrom-Json
                Write-Verbose "[Config] Loaded: $name.json"
            } catch {
                Write-Warning "[Config] Failed to parse $name.json: $_"
            }
        } else {
            Write-Warning "[Config] Not found: $name.json"
        }
    }
}

$configs = $global:sync.configs

# â"€â"€ 5. Resolve XAML â"€â"€
# Compiled mode: $inputXML is already set by Compile.ps1 output (Base64-decoded)
# Dev mode: load from disk
if (-not (Get-Variable 'inputXML' -Scope Script -ErrorAction SilentlyContinue) -and
    -not (Get-Variable 'inputXML' -Scope Global -ErrorAction SilentlyContinue)) {
    $xamlPath = Join-Path $Root "xaml\MainWindow.xaml"
    if (-not (Test-Path $xamlPath)) {
        [System.Windows.MessageBox]::Show(
            "MainWindow.xaml not found:`n$xamlPath",
            "WinTweak Utility"
        ) | Out-Null
        exit 1
    }
    $inputXML = Get-Content $xamlPath -Raw
}

# â"€â"€ 6. Final XAML validation (Step 2) before passing to UI â"€â"€
# Guards against empty $inputXML from a failed Base64 decode or missing embed
if ([string]::IsNullOrWhiteSpace($inputXML)) {
    [System.Windows.MessageBox]::Show(
        "XAML string is empty.`nRebuild with: .\Compile.ps1`nThen run with: powershell -Sta -File WinTweakUtility.ps1",
        "WinTweak Utility - Build Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}
Write-Verbose "[main] XAML length: $($inputXML.Length) chars"

# â"€â"€ 7. Launch WPF UI (requires -Sta mode - enforced by Compile.ps1 -Run) â"€â"€
Initialize-WTUUI -InputXML $inputXML -Config $configs

