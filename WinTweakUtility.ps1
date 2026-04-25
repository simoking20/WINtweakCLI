# =============================================================
#  WinTweak Utility v3.0  [COMPILED - DO NOT EDIT DIRECTLY]
#  Generated : 2026-04-23 11:06:14
#  Source    : github.com/SIMO-Dev/WinTweakUtility
# =============================================================

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- PRIVATE: Backup-WTURegistry.ps1 ---
function Backup-WTURegistry {
<#
.SYNOPSIS  Exports a registry path to a .reg file for backup/restore.
.PARAMETER Path       Registry path (HKLM:\... or HKCU:\...).
.PARAMETER OutputFile Optional .reg file destination. Auto-generated if omitted.
.EXAMPLE  Backup-WTURegistry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OutputFile = ""
    )

    $BackupDir = "$env:LOCALAPPDATA\WinTweakUtility\Backups"
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    if (-not $OutputFile) {
        $SafeName   = $Path -replace '[:\\]', '_'
        $OutputFile = Join-Path $BackupDir "${SafeName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    }

    # Convert PowerShell path to reg.exe path
    $RegPath = $Path -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                     -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
                     -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\'

    reg export "$RegPath" "$OutputFile" /y 2>&1 | Out-Null

    if (Test-Path $OutputFile) {
        Write-Verbose "[Backup] Registry exported: $OutputFile"
        return $OutputFile
    } else {
        Write-Warning "[Backup] Failed to export: $Path"
        return $null
    }
}

function Restore-WTURegistry {
<#
.SYNOPSIS  Imports a previously exported .reg backup file.
.PARAMETER BackupFile  Path to the .reg file to import.
.EXAMPLE  Restore-WTURegistry -BackupFile "C:\...\backup.reg"
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupFile)

    if (-not (Test-Path $BackupFile)) {
        throw "Backup file not found: $BackupFile"
    }
    reg import "$BackupFile" 2>&1 | Out-Null
    Write-Verbose "[Restore] Registry imported: $BackupFile"
}


# --- PRIVATE: Get-WTUOriginalValue.ps1 ---
function Get-WTUOriginalValue {
<#
.SYNOPSIS  Reads the current registry value and stores it as the 'OriginalValue' for undo.
.PARAMETER Path  Registry path (HKLM:\ or HKCU:\).
.PARAMETER Name  Registry value name.
.OUTPUTS   The current value, or $null if not found.
.EXAMPLE   $orig = Get-WTUOriginalValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        if (Test-Path $Path) {
            $val = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            return $val.$Name
        }
    }
    catch {
        Write-Verbose "[GetOriginal] Not found: $Path\$Name"
    }
    return $null
}

function Set-WTURegistryEntry {
<#
.SYNOPSIS  Sets a registry value, creating the key path if it doesn't exist.
.PARAMETER Path   Registry path.
.PARAMETER Name   Value name.
.PARAMETER Value  Value to set.
.PARAMETER Type   Registry type (DWord, String, QWord, Binary, ExpandString).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]        $Value,
        [string]$Type = "DWord"
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Verbose "[Registry] Set $Path\$Name = $Value ($Type)"
}


# --- PRIVATE: Invoke-WTUSafeExecution.ps1 ---
function Invoke-WTUSafeExecution {
<#
.SYNOPSIS  Wraps a script block with pre-backup, execution, logging, and rollback on failure.
.PARAMETER ScriptBlock  Code to execute.
.PARAMETER TweakName    Name for logging.
.PARAMETER BackupPath   Optional registry path to back up before executing.
.PARAMETER UndoBlock    Rollback script block if execution fails.
.EXAMPLE
    Invoke-WTUSafeExecution -TweakName "DisableTelemetry" -ScriptBlock {
        Set-ItemProperty 'HKLM:\...' -Name AllowTelemetry -Value 0
    } -UndoBlock {
        Set-ItemProperty 'HKLM:\...' -Name AllowTelemetry -Value 1
    }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$TweakName  = "Unknown",
        [string]$BackupPath = "",
        [scriptblock]$UndoBlock = $null
    )

    $backupFile = $null
    $before = "pre-execution"

    # Optional registry backup
    if ($BackupPath) {
        try { $backupFile = Backup-WTURegistry -Path $BackupPath }
        catch { Write-Warning "[Safe] Backup failed: $_" }
    }

    try {
        & $ScriptBlock
        Write-WTULog -Action "Execute" -Tweak $TweakName -Before $before -After "applied" -Success $true
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-WTULog -Action "Execute" -Tweak $TweakName -Before $before -After "FAILED" -Success $false -Error $errMsg
        Write-Warning "[Safe] $TweakName FAILED: $errMsg"

        # Attempt rollback
        if ($UndoBlock) {
            Write-Host "[Safe] Rolling back $TweakName..." -ForegroundColor Yellow
            try {
                & $UndoBlock
                Write-Host "[Safe] Rollback successful." -ForegroundColor Green
            } catch {
                Write-Warning "[Safe] Rollback also failed: $($_.Exception.Message)"
                if ($backupFile) {
                    Write-Host "[Safe] Restoring registry from backup..." -ForegroundColor Yellow
                    Restore-WTURegistry -BackupFile $backupFile
                }
            }
        }
        throw
    }
}


# --- PRIVATE: Test-WTUAdmin.ps1 ---
function Test-WTUAdmin {
<#
.SYNOPSIS  Verifies current process has Administrator privileges.
.DESCRIPTION  Throws a terminating error if not elevated.
.EXAMPLE  Test-WTUAdmin
#>
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator privileges required. Right-click WinTweakUtility.ps1 -> Run as Administrator."
    }
}


# --- PRIVATE: Test-WTUConfig.ps1 ---
function Test-WTUConfig {
<#
.SYNOPSIS  Validates a WinTweak Utility config JSON object against required fields.
.PARAMETER Config     Parsed JSON object (PSCustomObject) from a config file.
.PARAMETER ConfigName Name of the config for error messages.
.EXAMPLE  Test-WTUConfig -Config ($json | ConvertFrom-Json) -ConfigName "gaming.json"
.OUTPUTS  [bool] $true if valid, throws on invalid.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [string]$ConfigName = "config"
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($prop in $Config.PSObject.Properties) {
        $entry = $prop.Value
        $name  = $prop.Name

        if ([string]::IsNullOrWhiteSpace($entry.Content)) {
            $errors.Add("[$name] Missing required field: Content")
        }
        if ([string]::IsNullOrWhiteSpace($entry.Description)) {
            $errors.Add("[$name] Missing required field: Description")
        }
        # Validate Registry entries if present
        if ($entry.Registry) {
            foreach ($reg in $entry.Registry) {
                if (-not $reg.Path) { $errors.Add("[$name] Registry entry missing Path") }
                if (-not $reg.Name) { $errors.Add("[$name] Registry entry missing Name") }
            }
        }
    }

    if ($errors.Count -gt 0) {
        $msg = "Config validation failed for '$ConfigName':`n" + ($errors -join "`n")
        throw $msg
    }

    Write-Verbose "[Validate] $ConfigName OK ($($Config.PSObject.Properties.Count) entries)"
    return $true
}


# --- PRIVATE: Write-WTULog.ps1 ---
function Write-WTULog {
<#
.SYNOPSIS  Writes a structured JSONL log entry and human-readable console output.
.PARAMETER Action   The action category (e.g. Tweak, Gaming, Repair).
.PARAMETER Tweak    The specific tweak/entry name.
.PARAMETER Before   State before the action.
.PARAMETER After    State after the action.
.PARAMETER Success  Whether the action succeeded.
.PARAMETER Error    Optional error message.
.EXAMPLE  Write-WTULog -Action Tweak -Tweak WPFTweaksTelemetry -Before "Enabled" -After "Disabled" -Success $true
#>
    [CmdletBinding()]
    param(
        [string]$Action  = "Unknown",
        [string]$Tweak   = "",
        [string]$Before  = "",
        [string]$After   = "",
        [bool]  $Success = $true,
        [string]$Error   = ""
    )

    $LogDir  = "$env:LOCALAPPDATA\WinTweakUtility\Logs"
    $LogFile = Join-Path $LogDir "$(Get-Date -Format 'yyyyMM').jsonl"

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $entry = [PSCustomObject]@{
        timestamp = (Get-Date -Format 'o')
        action    = $Action
        tweak     = $Tweak
        user      = $env:USERNAME
        computer  = $env:COMPUTERNAME
        before    = $Before
        after     = $After
        success   = $Success
        error     = $Error
    }

    # JSONL append
    ($entry | ConvertTo-Json -Compress) | Add-Content -Path $LogFile -Encoding UTF8

    # Console output
    $color = if ($Success) { 'Green' } else { 'Red' }
    $symbol = if ($Success) { '[+]' } else { '[!]' }
    Write-Host "$symbol [$Action] $Tweak" -ForegroundColor $color
    if ($Error) { Write-Host "    Error: $Error" -ForegroundColor Red }
}


# --- PUBLIC: Initialize-WTUUI.ps1 ---
function Find-WTUControl {
<#
.SYNOPSIS  Null-safe wrapper around Window.FindName. Warns if control is missing.
           Defined at script scope so the PS parser doesn't flag nested-function depth.
.PARAMETER Window  The WPF Window object.
.PARAMETER Name    The x:Name of the control to find.
#>
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Name
    )
    $ctrl = $Window.FindName($Name)
    if (-not $ctrl) {
        Write-Warning "[UI] Control not found: '$Name' - check x:Name in XAML"
    }
    return $ctrl
}

function Initialize-WTUUI {
<#
.SYNOPSIS  Loads the WPF MainWindow XAML, wires all events, and shows the UI.
.PARAMETER InputXML  Raw XAML string for the main window.
.PARAMETER Config    Hashtable of parsed JSON configs (applications, tweaks, gaming, features, repairs, dns).
.EXAMPLE  Initialize-WTUUI -InputXML $inputXML -Config $sync.configs
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]    $InputXML,
        [Parameter(Mandatory)][hashtable] $Config
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    # Step 2: Validate XAML string is not empty before attempting to load
    if ([string]::IsNullOrWhiteSpace($InputXML)) {
        throw "XAML string is empty. Rebuild with Compile.ps1 and verify MainWindow.xaml was embedded."
    }
    Write-Verbose "[UI] XAML length: $($InputXML.Length) chars"

    # Step 3: Correct XAML load pattern â€” XmlReader.Create(StringReader) not [xml] cast
    # [xml] cast loses namespace context; XmlNodeReader drops x:Name in some PS versions
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($InputXML))

    # Step 8: try/catch so XAML parse errors are visible instead of silent crash
    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        $msg = "XAML Load Failed:`n$($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        if ([System.Management.Automation.PSTypeName]'System.Windows.MessageBox' -as [type]) {
            [System.Windows.MessageBox]::Show($msg, "WinTweak Utility - XAML Error") | Out-Null
        }
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ---- Populate Install tab ----
    $installPanel = Find-WTUControl $window 'InstallPanel'
    if ($Config.applications) {
        $grouped = $Config.applications.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Foreground = [System.Windows.Media.Brushes]::CornflowerBlue
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in ($g.Group | Sort-Object { $_.Value.Content })) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $item.Value.Content
                $cb.ToolTip = $item.Value.Description
                $cb.Tag     = $item.Name
                $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                $sp.Children.Add($cb) | Out-Null
            }
            $gb.Content = $sp
            if ($installPanel) { $installPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Tweaks tab ----
    $tweaksPanel = Find-WTUControl $window 'TweaksPanel'
    if ($Config.tweaks) {
        $grouped = $Config.tweaks.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $type = $item.Value.Type
                if ($type -in 'CheckBox','Toggle') {
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.Content = $item.Value.Content
                    $cb.ToolTip = $item.Value.Description
                    $cb.Tag     = $item.Name
                    $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                    $sp.Children.Add($cb) | Out-Null
                } elseif ($type -eq 'Button') {
                    $btn = New-Object System.Windows.Controls.Button
                    $btn.Content = $item.Value.Content
                    $btn.ToolTip = $item.Value.Description
                    $btn.Tag     = $item.Name
                    $btn.Margin  = [System.Windows.Thickness]::new(0,4,0,4)
                    $sp.Children.Add($btn) | Out-Null
                }
            }
            $gb.Content = $sp
            if ($tweaksPanel) { $tweaksPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Gaming modes ----
    $modesPanel = Find-WTUControl $window 'GamingModesPanel'
    $modeColors = @{
        'WTFModeUltimate'          = '#69F0AE'
        'WTFModeCompetitiveStable' = '#4FC3F7'
        'WTFModeLatency'           = '#4FC3F7'
        'WTFModeEsports'           = '#FFB74D'
        'WTFModeStable'            = '#FFEB3B'
        'WTFModeLaptop'            = '#64B5F6'
        'WTFModeBattery'           = '#9E9E9E'
    }
    if ($Config.gaming) {
        $modes = $Config.gaming.PSObject.Properties | Where-Object { $_.Value.category -eq 'Gaming Performance Modes' }
        foreach ($m in $modes) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content    = $m.Value.Content
            $btn.ToolTip    = $m.Value.Description
            $btn.Tag        = $m.Name
            $btn.Margin     = [System.Windows.Thickness]::new(0,3,0,3)
            $btn.HorizontalAlignment = 'Stretch'
            $color = if ($modeColors[$m.Name]) { $modeColors[$m.Name] } else { '#C8C8D8' }
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($color)
            if ($modesPanel) { $modesPanel.Children.Add($btn) | Out-Null }
        }
    }

    # ---- Populate Gaming individual tweaks ----
    $tweaksPanelG = Find-WTUControl $window 'GamingTweaksPanel'
    if ($Config.gaming) {
        $indiv = $Config.gaming.PSObject.Properties | Where-Object { $_.Value.category -eq 'Gaming Individual Tweaks' }
        foreach ($t in $indiv) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $t.Value.Content
            $cb.ToolTip = if ($t.Value.Description) { $t.Value.Description } else { $t.Value.Content }
            $cb.Tag     = $t.Name
            $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
            if ($tweaksPanelG) { $tweaksPanelG.Children.Add($cb) | Out-Null }
        }
    }

    # ---- Populate Features tab ----
    $featPanel = Find-WTUControl $window 'FeaturesPanel'
    if ($Config.features) {
        $grouped = $Config.features.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $item.Value.Content
                $cb.ToolTip = $item.Value.Description
                $cb.Tag     = $item.Name
                $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                $sp.Children.Add($cb) | Out-Null
            }
            $gb.Content = $sp
            if ($featPanel) { $featPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Repair tab ----
    $repairPanel = Find-WTUControl $window 'RepairPanel'
    if ($Config.repairs) {
        $grouped = $Config.repairs.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $btn = New-Object System.Windows.Controls.Button
                $btn.Content    = $item.Value.Content
                $btn.ToolTip    = $item.Value.Description
                $btn.Tag        = $item.Name
                $btn.Margin     = [System.Windows.Thickness]::new(0,4,0,4)
                $btn.HorizontalAlignment = 'Stretch'
                $sp.Children.Add($btn) | Out-Null
            }
            $gb.Content = $sp
            if ($repairPanel) { $repairPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate DNS tab ----
    $dnsPanel = Find-WTUControl $window 'DNSPanel'
    if ($Config.dns) {
        foreach ($d in $Config.dns.PSObject.Properties) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $d.Value.Content
            $btn.ToolTip = $d.Value.Description
            $btn.Tag     = $d.Name
            $btn.Margin  = [System.Windows.Thickness]::new(0,0,8,8)
            if ($dnsPanel) { $dnsPanel.Children.Add($btn) | Out-Null }
        }
    }

    # ---- GPU Slider live update (Step 4: null-guard before wiring) ----
    $gpuClockSlider = Find-WTUControl $window 'GPUClockSlider'
    $gpuClockValue  = Find-WTUControl $window 'GPUClockValue'
    $gpuPowerSlider = Find-WTUControl $window 'GPUPowerSlider'
    $gpuPowerValue  = Find-WTUControl $window 'GPUPowerValue'

    if ($gpuClockSlider -and $gpuClockValue) {
        $gpuClockSlider.Add_ValueChanged({ $gpuClockValue.Text = [int]$gpuClockSlider.Value })
    }
    if ($gpuPowerSlider -and $gpuPowerValue) {
        $gpuPowerSlider.Add_ValueChanged({ $gpuPowerValue.Text = "$([int]$gpuPowerSlider.Value)%" })
    }

    # ---- Show window (Step 3: .ShowDialog() not .Show()) ----
    $window.ShowDialog() | Out-Null
}


# --- PUBLIC: Invoke-WTUAppManager.ps1 ---
function Invoke-WTUAppManager {
<#
.SYNOPSIS  Installs or uninstalls applications defined in applications.json.
.PARAMETER AppName   Key name (e.g. WPFInstallChrome) or array of names.
.PARAMETER Config    Parsed applications.json object.
.PARAMETER Uninstall If specified, uninstalls instead of installing.
.EXAMPLE  Invoke-WTUAppManager -AppName @('WPFInstallChrome','WPFInstallDiscord') -Config $sync.configs.applications
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]     $AppName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Uninstall
    )

    $action = if ($Uninstall) { "Uninstall" } else { "Install" }

    # Check WinGet availability
    $hasWinGet = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $hasChoco  = $null -ne (Get-Command choco  -ErrorAction SilentlyContinue)

    if (-not $hasWinGet -and -not $hasChoco) {
        Write-Warning "Neither WinGet nor Chocolatey is available. Cannot manage apps."
        return
    }

    foreach ($name in $AppName) {
        $app = $Config.$name
        if (-not $app) { Write-Warning "App not found in config: $name"; continue }

        Write-Host "[$action] $($app.Content)..." -ForegroundColor Cyan

        $success = $false

        # Try WinGet first
        if ($hasWinGet -and $app.winget) {
            try {
                if ($Uninstall) {
                    winget uninstall --id $app.winget --silent --accept-source-agreements 2>&1 | Out-Null
                } else {
                    winget install --id $app.winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                }
                $success = $true
                Write-Host "  [OK] $($app.Content) via WinGet" -ForegroundColor Green
            } catch { Write-Warning "WinGet failed for $($app.Content): $_" }
        }

        # Chocolatey fallback
        if (-not $success -and $hasChoco -and $app.choco -and -not $Uninstall) {
            try {
                choco install $app.choco -y 2>&1 | Out-Null
                $success = $true
                Write-Host "  [OK] $($app.Content) via Chocolatey" -ForegroundColor Green
            } catch { Write-Warning "Choco failed: $_" }
        }

        if (-not $success) { Write-Warning "  [FAIL] Could not $action $($app.Content)" }
        Write-WTULog -Action "AppManager" -Tweak $name -After $action -Success $success
    }
}


# --- PUBLIC: Invoke-WTUBenchmark.ps1 ---
function Invoke-WTUBenchmark {
<#
.SYNOPSIS  Runs before/after performance benchmarks: CPU, disk, timer resolution, GPU.
.PARAMETER Phase  'Before', 'After', or '' (run both with comparison prompt).
.EXAMPLE  Invoke-WTUBenchmark -Phase Before
.EXAMPLE  Invoke-WTUBenchmark
#>
    [CmdletBinding()]
    param([ValidateSet('Before','After','')][string]$Phase = '')

    $ResultDir = "$env:LOCALAPPDATA\WinTweakUtility\Benchmarks"
    if (-not (Test-Path $ResultDir)) { New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }

    # Defer Add-Type inside function â€” safe when compiled inline
    if (-not ([System.Management.Automation.PSTypeName]'WTUBenchTimer').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUBenchTimer {
    [DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint min, out uint max, out uint cur);
}
"@ -ErrorAction SilentlyContinue
    }

    function Run-BenchmarkPhase([string]$label) {
        $ts     = Get-Date -Format 'yyyyMMdd_HHmmss'
        $result = [ordered]@{ Phase=$label; Timestamp=$ts }

        Write-Host "  [Benchmark] Phase: $label" -ForegroundColor Cyan

        # CPU (simple loop)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $x  = 0L
        for ($i = 1; $i -le 10000000; $i++) { $x += $i % 7 }
        $sw.Stop()
        $result['CPU_ms'] = $sw.ElapsedMilliseconds
        Write-Host "  CPU time: $($sw.ElapsedMilliseconds)ms  (value=$x)"

        # Disk write speed (50MB temp file)
        $testFile = Join-Path $env:TEMP "wtu_bench_$ts.tmp"
        $data     = New-Object byte[] (50 * 1024 * 1024)
        $sw.Restart()
        [System.IO.File]::WriteAllBytes($testFile, $data)
        $sw.Stop()
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        $diskMBps = if ($sw.ElapsedMilliseconds -gt 0) {
            [Math]::Round(50 / ($sw.ElapsedMilliseconds / 1000.0), 1)
        } else { 0.0 }
        $result['DiskWrite_MBps'] = $diskMBps
        Write-Host "  Disk Write: ${diskMBps} MB/s"

        # Timer resolution
        try {
            [uint]$tmn=0; [uint]$tmx=0; [uint]$tcur=0
            $null = [WTUBenchTimer]::NtQueryTimerResolution([ref]$tmn, [ref]$tmx, [ref]$tcur)
            $tmMs = [Math]::Round($tcur / 10000.0, 2)
            $result['TimerRes_ms'] = $tmMs
            Write-Host "  Timer Resolution: ${tmMs}ms"
        } catch {}

        # GPU
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            $gpuRaw = nvidia-smi --query-gpu=name,clocks.gr,clocks.mem,power.draw --format=csv,noheader 2>&1
            $result['GPU_Info'] = $gpuRaw
            Write-Host "  GPU: $gpuRaw"
        }

        return $result
    }

    if ($Phase -eq 'Before' -or $Phase -eq '') {
        $beforeResult = Run-BenchmarkPhase 'Before'
        $beforeResult | ConvertTo-Json | Set-Content (Join-Path $ResultDir "before_latest.json") -Encoding UTF8
        Write-Host "  Saved: before_latest.json" -ForegroundColor Green
    }

    if ($Phase -eq 'After' -or $Phase -eq '') {
        if ($Phase -eq '') {
            Write-Host "`n  Apply your optimizations, then press Enter to run After benchmark..."
            $null = Read-Host
        }
        $afterResult = Run-BenchmarkPhase 'After'
        $afterResult | ConvertTo-Json | Set-Content (Join-Path $ResultDir "after_latest.json") -Encoding UTF8

        $beforePath = Join-Path $ResultDir "before_latest.json"
        if (Test-Path $beforePath) {
            $b = Get-Content $beforePath | ConvertFrom-Json
            Write-Host "`n  === Benchmark Comparison ===" -ForegroundColor Cyan
            $cpuDelta  = $b.CPU_ms - $afterResult.CPU_ms
            Write-Host "  CPU time:   Before=$($b.CPU_ms)ms  After=$($afterResult.CPU_ms)ms  Delta=${cpuDelta}ms"
            Write-Host "  Disk Write: Before=$($b.DiskWrite_MBps)MB/s  After=$($afterResult.DiskWrite_MBps)MB/s"
            if ($afterResult.TimerRes_ms) {
                Write-Host "  Timer Res:  Before=$($b.TimerRes_ms)ms  After=$($afterResult.TimerRes_ms)ms"
            }
        }
    }
}


# --- PUBLIC: Invoke-WTUDNS.ps1 ---
function Invoke-WTUDNS {
<#
.SYNOPSIS  Applies a DNS provider configuration to all active network adapters.
.PARAMETER ProviderName  Key from dns.json (e.g. Cloudflare, Google, DefaultDHCP).
.PARAMETER Config        Parsed dns.json object.
.EXAMPLE  Invoke-WTUDNS -ProviderName Cloudflare -Config $sync.configs.dns
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $ProviderName,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $provider = $Config.$ProviderName
    if (-not $provider) { throw "DNS provider not found: $ProviderName" }

    Write-Host "[DNS] Setting: $($provider.Content)" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    foreach ($adapter in $adapters) {
        Write-Host "  Adapter: $($adapter.Name)" -ForegroundColor DarkGray
        try {
            if ($provider.IPv4Primary -eq '') {
                # Reset to DHCP
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-Host "  [OK] Reset to DHCP" -ForegroundColor Green
            } else {
                $dns4 = @($provider.IPv4Primary)
                if ($provider.IPv4Secondary) { $dns4 += $provider.IPv4Secondary }
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dns4
                Write-Host "  [OK] IPv4: $($dns4 -join ', ')" -ForegroundColor Green

                if ($provider.IPv6Primary) {
                    $dns6 = @($provider.IPv6Primary)
                    if ($provider.IPv6Secondary) { $dns6 += $provider.IPv6Secondary }
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dns6
                    Write-Host "  [OK] IPv6: $($dns6 -join ', ')" -ForegroundColor Green
                }
            }
        } catch {
            Write-Warning "  Failed on $($adapter.Name): $_"
        }
    }

    # Flush DNS cache
    Clear-DnsClientCache
    Write-Host "[DNS] Cache flushed. Done." -ForegroundColor Green
    Write-WTULog -Action "DNS" -Tweak $ProviderName -After "Applied" -Success $true
}


# --- PUBLIC: Invoke-WTUFeature.ps1 ---
function Invoke-WTUFeature {
<#
.SYNOPSIS  Enables or disables a Windows optional feature from features.json.
.PARAMETER FeatureName  Key from features.json (e.g. WPFFeatureWSL).
.PARAMETER Config       Parsed features.json object.
.PARAMETER Disable      If specified, runs DisableScript (UndoScript).
.EXAMPLE  Invoke-WTUFeature -FeatureName WPFFeatureWSL -Config $sync.configs.features
.EXAMPLE  Invoke-WTUFeature -FeatureName WPFFeatureHyperV -Config $sync.configs.features -Disable
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $FeatureName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Disable
    )

    $feat = $Config.$FeatureName
    if (-not $feat) { throw "Feature not found: $FeatureName" }

    $action = if ($Disable) { "Disable" } else { "Enable" }
    Write-Host "[$action] $($feat.Content)" -ForegroundColor Cyan
    if ($feat.Warning) { Write-Host "  [WARN] $($feat.Warning)" -ForegroundColor Yellow }
    if ($feat.RestartRequired) { Write-Host "  [INFO] Restart required." -ForegroundColor Yellow }

    Invoke-WTUSafeExecution -TweakName $FeatureName -ScriptBlock {
        $scripts = if ($Disable) { $feat.UndoScript } else { $feat.InvokeScript }
        foreach ($cmd in $scripts) { Invoke-Expression $cmd }
    }

    Write-WTULog -Action "Feature" -Tweak $FeatureName -After $action -Success $true
}


# --- PUBLIC: Invoke-WTUGamingMode.ps1 ---
function Invoke-WTUGamingMode {
<#
.SYNOPSIS  Applies or undoes a gaming performance mode from gaming.json.
.PARAMETER ModeName  Key name from gaming.json (e.g. WTFModeCompetitiveStable).
.PARAMETER Config    Parsed gaming.json object.
.PARAMETER Undo      If specified, runs UndoScript and restores OriginalValues.
.PARAMETER Force     Skips confirmation prompt.
.EXAMPLE  Invoke-WTUGamingMode -ModeName WTFModeCompetitiveStable -Config $sync.configs.gaming
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $ModeName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Undo,
        [switch]$Force
    )

    $mode = $Config.$ModeName
    if (-not $mode) { throw "Gaming mode not found: $ModeName" }

    $action = if ($Undo) { "Undo" } else { "Apply" }

    Write-Host ""
    Write-Host "  [$action] $($mode.Content)" -ForegroundColor Cyan
    if ($mode.Description) { Write-Host "  $($mode.Description)" -ForegroundColor Gray }
    if ($mode.EstimatedImpact) {
        $mode.EstimatedImpact.PSObject.Properties | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor DarkGray
        }
    }
    if ($mode.Warning) {
        Write-Host ""
        Write-Host "  [WARN] $($mode.Warning)" -ForegroundColor Yellow
    }
    if ($mode.RestartRequired -and -not $Undo) {
        Write-Host "  [INFO] Restart required after applying this mode." -ForegroundColor Yellow
    }

    if (-not $Force) {
        $confirm = Read-Host "`n  Confirm? (YES to proceed)"
        if ($confirm -ne "YES") {
            Write-Host "  Cancelled." -ForegroundColor Gray
            return
        }
    }

    # Auto-checkpoint before applying (not for undo)
    if (-not $Undo) {
        Write-Host "  [Checkpoint] Creating safety checkpoint..." -ForegroundColor DarkCyan
        Invoke-WTURollback -Action Create -Name "Before_$ModeName"
    }

    Invoke-WTUSafeExecution -TweakName $ModeName -ScriptBlock {

        if (-not $Undo) {
            # Registry
            foreach ($reg in $mode.Registry) {
                Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type
            }
            # Services
            foreach ($svc in $mode.Service) {
                try { Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction SilentlyContinue } catch {}
            }
            # InvokeScript
            foreach ($cmd in $mode.InvokeScript) {
                Invoke-Expression $cmd
            }
        } else {
            # Restore registry
            foreach ($reg in $mode.Registry) {
                if ($null -ne $reg.OriginalValue) {
                    Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.OriginalValue -Type $reg.Type
                }
            }
            # Restore services
            foreach ($svc in $mode.Service) {
                if ($svc.OriginalType) {
                    try { Set-Service -Name $svc.Name -StartupType $svc.OriginalType -ErrorAction SilentlyContinue } catch {}
                }
            }
            # UndoScript
            foreach ($cmd in $mode.UndoScript) {
                Invoke-Expression $cmd
            }
        }
    }

    Write-Host ""
    Write-Host "  [+] $($mode.Content) $action complete." -ForegroundColor Green
    Write-WTULog -Action "GamingMode" -Tweak $ModeName -After $action -Success $true
}


# --- PUBLIC: Invoke-WTUMonitor.ps1 ---
function Invoke-WTUMonitor {
<#
.SYNOPSIS  Real-time system performance monitor: GPU, CPU, RAM, timer resolution.
.PARAMETER RefreshSec  Update interval in seconds (default: 2).
.EXAMPLE  Invoke-WTUMonitor -RefreshSec 1
#>
    [CmdletBinding()]
    param([int]$RefreshSec = 2)

    Write-Host "`n  WinTweak Utility v3.0 - Real-Time Monitor  (Ctrl+C to stop)" -ForegroundColor Cyan
    Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray

    # Defer Add-Type inside function so it is safe when compiled inline
    if (-not ([System.Management.Automation.PSTypeName]'WTUMonitorTimer').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUMonitorTimer {
    [DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint min, out uint max, out uint cur);
}
"@ -ErrorAction SilentlyContinue
    }

    while ($true) {
        $line = ""

        # CPU load
        $cpuLoad = (Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue).LoadPercentage
        $cpuStr  = if ($cpuLoad) { "${cpuLoad}%" } else { "N/A" }
        $line   += "CPU: $cpuStr  "

        # RAM
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $usedMB  = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024)
            $totalMB = [Math]::Round($os.TotalVisibleMemorySize / 1024)
            $line   += "RAM: ${usedMB}/${totalMB}MB  "
        }

        # Timer resolution
        try {
            [uint]$tmn=0; [uint]$tmx=0; [uint]$tcur=0
            $null    = [WTUMonitorTimer]::NtQueryTimerResolution([ref]$tmn, [ref]$tmx, [ref]$tcur)
            $timerMs = [Math]::Round($tcur / 10000.0, 2)
            $line   += "Timer: ${timerMs}ms  "
        } catch {}

        # GPU (nvidia-smi)
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            $gpu = nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,clocks.gr,power.draw --format=csv,noheader 2>&1
            if ($gpu -notmatch 'error') {
                $parts = $gpu -split ', '
                if ($parts.Count -ge 4) {
                    $line += "GPU: $($parts[0])C  $($parts[1])  $($parts[2])MHz  $($parts[3])W"
                }
            }
        }

        Write-Host "`r  $line                    " -NoNewline -ForegroundColor White
        Start-Sleep -Seconds $RefreshSec
    }
}


# --- PUBLIC: Invoke-WTURepair.ps1 ---
function Invoke-WTURepair {
<#
.SYNOPSIS  Executes a system repair action from repairs.json.
.PARAMETER RepairName  Key from repairs.json (e.g. WTURepairWindowsUpdate).
.PARAMETER Config      Parsed repairs.json object.
.EXAMPLE  Invoke-WTURepair -RepairName WTURepairSFC -Config $sync.configs.repairs
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $RepairName,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $repair = $Config.$RepairName
    if (-not $repair) { throw "Repair not found: $RepairName" }

    Write-Host "[Repair] $($repair.Content)" -ForegroundColor Cyan
    if ($repair.Warning) { Write-Host "  [WARN] $($repair.Warning)" -ForegroundColor Yellow }

    Invoke-WTUSafeExecution -TweakName $RepairName -ScriptBlock {
        foreach ($cmd in $repair.InvokeScript) { Invoke-Expression $cmd }
    }

    Write-WTULog -Action "Repair" -Tweak $RepairName -After "Completed" -Success $true
}


# --- PUBLIC: Invoke-WTURollback.ps1 ---
function Invoke-WTURollback {
<#
.SYNOPSIS  Create, list, restore, delete, or compare system checkpoints.
.PARAMETER Action      Create | List | Restore | Delete | Compare.
.PARAMETER Name        Checkpoint name (for Create).
.PARAMETER Index       Checkpoint index number (for Restore/Delete).
.PARAMETER CompareA    First checkpoint index (for Compare).
.PARAMETER CompareB    Second checkpoint index (for Compare).
.PARAMETER Interactive Prompt user to select checkpoint interactively.
.EXAMPLE  Invoke-WTURollback -Action Create -Name "Before_Gaming"
.EXAMPLE  Invoke-WTURollback -Action Restore -Interactive
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Create','List','Restore','Delete','Compare')][string]$Action,
        [string]$Name      = "Checkpoint",
        [int]   $Index     = 0,
        [int]   $CompareA  = 0,
        [int]   $CompareB  = 1,
        [switch]$Interactive
    )

    $CheckpointDir = "$env:LOCALAPPDATA\WinTweakUtility\Checkpoints"
    $IndexFile     = Join-Path $CheckpointDir "index.txt"
    if (-not (Test-Path $CheckpointDir)) { New-Item -ItemType Directory -Path $CheckpointDir -Force | Out-Null }
    if (-not (Test-Path $IndexFile))     { New-Item -ItemType File -Path $IndexFile -Force | Out-Null }

    switch ($Action) {

        'Create' {
            $ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
            $slug = "checkpoint_${ts}"
            $dir  = Join-Path $CheckpointDir $slug
            New-Item -ItemType Directory -Path $dir | Out-Null

            # Save registry key snapshots
            $keys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
                'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers',
                'HKCU:\System\GameConfigStore',
                'HKCU:\Control Panel\Mouse'
            )
            foreach ($k in $keys) {
                $safe = ($k -replace '[:\\]','_')
                Backup-WTURegistry -Path $k -OutputFile (Join-Path $dir "${safe}.reg")
            }

            # Save power plan
            powercfg /getactivescheme 2>&1 | Out-File (Join-Path $dir "powerplan.txt")

            # Save GPU state
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                nvidia-smi --query-gpu=name,clocks.gr,clocks.mem,power.limit --format=csv 2>&1 | Out-File (Join-Path $dir "gpu_state.txt")
            }

            # Save metadata
            @{ name=$Name; timestamp=$ts; user=$env:USERNAME } | ConvertTo-Json | Set-Content (Join-Path $dir "meta.json")
            Add-Content $IndexFile "${slug}|${Name}|${ts}"
            Write-Host "[Checkpoint] Created: $slug ($Name)" -ForegroundColor Green
            Write-WTULog -Action "Checkpoint" -Tweak "Create" -After $slug -Success $true
        }

        'List' {
            $entries = Get-Content $IndexFile -ErrorAction SilentlyContinue
            if (-not $entries) { Write-Host "  No checkpoints found." -ForegroundColor Yellow; return }
            Write-Host "`n  Checkpoints:" -ForegroundColor Cyan
            $i = 1
            foreach ($e in $entries) {
                $parts = $e -split '\|'
                Write-Host "  [$i] $($parts[0]) - $($parts[1]) ($($parts[2]))"
                $i++
            }
            Write-Host ""
        }

        'Restore' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if (-not $entries) { Write-Host "  No checkpoints to restore." -ForegroundColor Yellow; return }

            if ($Interactive) {
                Invoke-WTURollback -Action List
                $sel = Read-Host "  Select checkpoint number"
                $Index = [int]$sel
            }

            if ($Index -lt 1 -or $Index -gt $entries.Count) { Write-Warning "Invalid index: $Index"; return }
            $slug = ($entries[$Index - 1] -split '\|')[0]
            $dir  = Join-Path $CheckpointDir $slug

            Write-Host "  [Restore] Restoring from: $slug..." -ForegroundColor Yellow
            Get-ChildItem $dir -Filter "*.reg" | ForEach-Object { Restore-WTURegistry -BackupFile $_.FullName }
            $pp = Get-Content (Join-Path $dir "powerplan.txt") -ErrorAction SilentlyContinue
            if ($pp -match 'GUID: ([0-9a-f-]+)') { powercfg -setactive $Matches[1] 2>&1 | Out-Null }
            Write-Host "  [+] Restore complete." -ForegroundColor Green
            Write-WTULog -Action "Checkpoint" -Tweak "Restore" -After $slug -Success $true
        }

        'Delete' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if ($Interactive) {
                Invoke-WTURollback -Action List
                $sel   = Read-Host "  Select checkpoint number to delete"
                $Index = [int]$sel
            }
            if ($Index -lt 1 -or $Index -gt $entries.Count) { Write-Warning "Invalid index"; return }
            $slug = ($entries[$Index - 1] -split '\|')[0]
            $dir  = Join-Path $CheckpointDir $slug
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            $newEntries = $entries | Where-Object { $_ -notmatch "^$slug\|" }
            $newEntries | Set-Content $IndexFile
            Write-Host "  [Deleted] $slug" -ForegroundColor Green
        }

        'Compare' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if ($entries.Count -lt 2) { Write-Host "  Need at least 2 checkpoints to compare." -ForegroundColor Yellow; return }
            $aSlug = ($entries[$CompareA - 1] -split '\|')[0]
            $bSlug = ($entries[$CompareB - 1] -split '\|')[0]
            Write-Host "`n  Comparing [$CompareA] $aSlug vs [$CompareB] $bSlug" -ForegroundColor Cyan
            $aDir = Join-Path $CheckpointDir $aSlug
            $bDir = Join-Path $CheckpointDir $bSlug
            $aMeta = Get-Content (Join-Path $aDir "meta.json") | ConvertFrom-Json
            $bMeta = Get-Content (Join-Path $bDir "meta.json") | ConvertFrom-Json
            Write-Host "  A: $($aMeta.name) created $($aMeta.timestamp)"
            Write-Host "  B: $($bMeta.name) created $($bMeta.timestamp)"
            # Power plan comparison
            $aP = Get-Content (Join-Path $aDir "powerplan.txt") -EA SilentlyContinue
            $bP = Get-Content (Join-Path $bDir "powerplan.txt") -EA SilentlyContinue
            if ($aP -ne $bP) { Write-Host "  PowerPlan changed between checkpoints." -ForegroundColor Yellow }
            Write-Host ""
        }
    }
}


# --- PUBLIC: Invoke-WTUTweak.ps1 ---
function Invoke-WTUTweak {
<#
.SYNOPSIS  Applies or undoes a system tweak from tweaks.json.
.PARAMETER TweakName  Key name from tweaks.json (e.g. WPFTweaksTelemetry).
.PARAMETER Config     Parsed tweaks.json object.
.PARAMETER Undo       If specified, runs UndoScript and restores OriginalValues.
.EXAMPLE  Invoke-WTUTweak -TweakName WPFTweaksTelemetry -Config $sync.configs.tweaks
.EXAMPLE  Invoke-WTUTweak -TweakName WPFTweaksTelemetry -Config $sync.configs.tweaks -Undo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $TweakName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Undo
    )

    $entry = $Config.$TweakName
    if (-not $entry) { throw "Tweak not found: $TweakName" }

    $mode = if ($Undo) { "Undo" } else { "Apply" }
    Write-Host "[$mode] $($entry.Content)" -ForegroundColor Cyan

    Invoke-WTUSafeExecution -TweakName $TweakName -ScriptBlock {

        if (-not $Undo) {
            # ---- APPLY ----
            # Registry
            foreach ($reg in $entry.Registry) {
                Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type
            }
            # Services
            foreach ($svc in $entry.Service) {
                try { Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction SilentlyContinue } catch {}
            }
            # InvokeScript
            foreach ($cmd in $entry.InvokeScript) {
                Invoke-Expression $cmd
            }
            # Remove AppX packages
            foreach ($pkg in $entry.Appx) {
                Get-AppxPackage $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            }
        } else {
            # ---- UNDO ----
            # Restore registry OriginalValues
            foreach ($reg in $entry.Registry) {
                if ($null -ne $reg.OriginalValue) {
                    Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.OriginalValue -Type $reg.Type
                }
            }
            # Restore services
            foreach ($svc in $entry.Service) {
                if ($svc.OriginalType) {
                    try { Set-Service -Name $svc.Name -StartupType $svc.OriginalType -ErrorAction SilentlyContinue } catch {}
                }
            }
            # UndoScript
            foreach ($cmd in $entry.UndoScript) {
                Invoke-Expression $cmd
            }
        }
    }

    Write-WTULog -Action "Tweak" -Tweak $TweakName -After $mode -Success $true
}


# --- MODULE: gpu-amd.psm1 ---
<#
.SYNOPSIS  AMD GPU control (ULPS, Anti-Lag, power tuning via registry).
#>

function Test-WTUAMDAvailable {
    return (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000")
}

function Disable-WTUAMDUlps {
    $base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
        $val = Get-ItemProperty $_.PSPath -Name EnableUlps -EA SilentlyContinue
        if ($null -ne $val) {
            Set-ItemProperty $_.PSPath -Name EnableUlps -Value 0 -Type DWord -Force
        }
    }
    Write-Host "[AMD] ULPS disabled" -ForegroundColor Green
}

function Enable-WTUAMDAntiLag {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\AMD\DirectX" -Name "AntiLag" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "[AMD] Anti-Lag enabled" -ForegroundColor Green
}



# --- MODULE: gpu-intel.psm1 ---
<#
.SYNOPSIS  Intel GPU / iGPU power control via registry.
#>

function Set-WTUIntelPowerPreference {
    param([ValidateSet('MaxPerformance','Balanced','PowerSave')][string]$Mode)
    $val = switch ($Mode) { 'MaxPerformance' { 1 } 'Balanced' { 2 } 'PowerSave' { 3 } }
    $base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -Name DriverDesc -EA SilentlyContinue
        if ($p.DriverDesc -match 'Intel') {
            Set-ItemProperty $_.PSPath -Name PowerPolicy -Value $val -Type DWord -Force -EA SilentlyContinue
        }
    }
    Write-Host "[Intel GPU] Power mode set: $Mode" -ForegroundColor Green
}



# --- MODULE: gpu-nvidia.psm1 ---
<#
.SYNOPSIS  NVIDIA GPU control via nvidia-smi. Lock/unlock clocks, power limits.
#>

function Test-WTUNVIDIAAvailable {
    return $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
}

function Get-WTUNVIDIAInfo {
    if (-not (Test-WTUNVIDIAAvailable)) { return $null }
    $raw = nvidia-smi --query-gpu=name,driver_version,power.limit,clocks.gr,clocks.mem,temperature.gpu --format=csv,noheader 2>&1
    $parts = $raw -split ', '
    return @{ Name=$parts[0]; Driver=$parts[1]; PowerLimitW=$parts[2]; CoreMHz=$parts[3]; MemMHz=$parts[4]; TempC=$parts[5] }
}

function Invoke-WTUNVIDIALockClocks {
    param([int]$CoreMHz, [int]$MemMHz = 6000)
    if (-not (Test-WTUNVIDIAAvailable)) { Write-Warning "nvidia-smi not found"; return }
    nvidia-smi -lgc $CoreMHz 2>&1 | Out-Null
    nvidia-smi -lmc $MemMHz  2>&1 | Out-Null
    Write-Host "[NVIDIA] Clocks locked: ${CoreMHz}MHz core / ${MemMHz}MHz mem" -ForegroundColor Green
}

function Invoke-WTUNVIDIAUnlockClocks {
    if (-not (Test-WTUNVIDIAAvailable)) { return }
    nvidia-smi -rgc 2>&1 | Out-Null
    nvidia-smi -rmc 2>&1 | Out-Null
    Write-Host "[NVIDIA] Clocks unlocked" -ForegroundColor Green
}

function Set-WTUNVIDIAPowerLimit {
    param([int]$MaxPowerW, [int]$Percent)
    if (-not (Test-WTUNVIDIAAvailable)) { return }
    $limit = [Math]::Round($MaxPowerW * $Percent / 100)
    nvidia-smi -pl $limit 2>&1 | Out-Null
    Write-Host "[NVIDIA] Power limit: ${limit}W (${Percent}% of ${MaxPowerW}W)" -ForegroundColor Green
}

function Enable-WTUNVIDIAPersistence {
    if (-not (Test-WTUNVIDIAAvailable)) { return }
    nvidia-smi -pm 1 2>&1 | Out-Null
}



# --- MODULE: memory.psm1 ---
<#
.SYNOPSIS  RAM cleanup and standby list purge module.
           Add-Type is deferred into a private helper so it is safe when
           inlined by Compile.ps1 â€” not evaluated until the function runs.
#>

function Initialize-WTUMemoryType {
    if (-not ([System.Management.Automation.PSTypeName]'WTUMemory').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUMemory {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
"@ -ErrorAction SilentlyContinue
    }
}

function Clear-WTUStandbyList {
<#
.SYNOPSIS  Clears the memory standby list. Falls back to working set trim.
.NOTE      Full standby-list purge requires RAMMap or NtSetSystemInformation (admin).
#>
    Initialize-WTUMemoryType

    $procs = Get-Process -ErrorAction SilentlyContinue
    $trimmed = 0
    foreach ($p in $procs) {
        try {
            [WTUMemory]::EmptyWorkingSet($p.Handle) | Out-Null
            $trimmed++
        } catch {}
    }
    Write-Host "[Memory] Working sets trimmed across $trimmed processes" -ForegroundColor Green

    $rammap = Get-Command RAMMap.exe -ErrorAction SilentlyContinue
    if ($rammap) {
        Start-Process RAMMap.exe -ArgumentList "-AcceptEula -Et" -Wait -WindowStyle Hidden
        Write-Host "[Memory] RAMMap standby list purged" -ForegroundColor Green
    }
}

function Get-WTUMemoryStats {
    $os     = Get-CimInstance Win32_OperatingSystem
    $freeMB  = [Math]::Round($os.FreePhysicalMemory / 1024)
    $totalMB = [Math]::Round($os.TotalVisibleMemorySize / 1024)
    $usedMB  = $totalMB - $freeMB
    return @{
        UsedMB  = $usedMB
        FreeMB  = $freeMB
        TotalMB = $totalMB
        UsedPct = [Math]::Round($usedMB * 100 / $totalMB)
    }
}



# --- MODULE: network.psm1 ---
<#
.SYNOPSIS  TCP/IP network optimization module for gaming.
#>

function Optimize-WTUNetworkGaming {
    # Nagle's algorithm
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' `
        -Name TcpAckFrequency -Value 1 -Type DWord -Force -EA SilentlyContinue
    # Network throttling index (gaming: 0xFFFFFFFF = disabled)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
        -Name NetworkThrottlingIndex -Value 0xFFFFFFFF -Type DWord -Force -EA SilentlyContinue
    # Game scheduling priority
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
        -Name 'GPU Priority' -Value 8 -Type DWord -Force -EA SilentlyContinue
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
        -Name 'Priority' -Value 6 -Type DWord -Force -EA SilentlyContinue
    # Disable auto-tuning (can help on some configs)
    netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    netsh int tcp set global chimney=disabled 2>&1 | Out-Null
    netsh int tcp set global rss=enabled 2>&1 | Out-Null
    Write-Host "[Network] Gaming TCP optimization applied" -ForegroundColor Green
}

function Restore-WTUNetworkDefaults {
    netsh int tcp set global autotuninglevel=normal  2>&1 | Out-Null
    netsh int tcp set global chimney=enabled          2>&1 | Out-Null
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
        -Name NetworkThrottlingIndex -Force -EA SilentlyContinue
    Write-Host "[Network] Defaults restored" -ForegroundColor Green
}



# --- MODULE: power.psm1 ---
<#
.SYNOPSIS  Power plan management module.
#>

$PLANS = @{
    Balanced       = '381b4222-f694-41f0-9685-ff5bb260df2e'
    HighPerformance= '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    PowerSaver     = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    Ultimate       = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
}

function Get-WTUActivePowerPlan {
    $line = powercfg /getactivescheme 2>&1
    if ($line -match 'GUID: ([0-9a-f-]+)\s+\((.+)\)') {
        return @{ GUID=$Matches[1]; Name=$Matches[2] }
    }
    return $null
}

function Set-WTUPowerPlan {
    param([ValidateSet('Balanced','HighPerformance','PowerSaver','Ultimate')][string]$Plan)
    $guid = $PLANS[$Plan]
    if ($Plan -eq 'Ultimate') {
        powercfg -duplicatescheme $guid 2>&1 | Out-Null
    }
    powercfg -setactive $guid 2>&1 | Out-Null
    Write-Host "[Power] Active plan: $Plan ($guid)" -ForegroundColor Green
}



# --- MODULE: process.psm1 ---
<#
.SYNOPSIS  CPU affinity and process priority management for gaming.
#>

function Set-WTUProcessGamingPriority {
    param([string]$ProcessName, [ValidateSet('Normal','High','RealTime')][string]$Priority = 'High')
    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $p.PriorityClass = $Priority
        Write-Host "[Process] $ProcessName -> Priority: $Priority" -ForegroundColor Green
    }
}

function Enable-WTUCoreIsolation {
    param([int]$ReservedCores = 2)
    $totalCores = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
    if ($totalCores -le $ReservedCores) { Write-Warning "Not enough cores to isolate"; return }
    # Set affinity mask leaving top cores for OS
    $mask = [Math]::Pow(2, $totalCores) - 1 - ([Math]::Pow(2, $ReservedCores) - 1)
    Write-Host "[Process] Core isolation: $ReservedCores cores reserved for OS (mask: $([Convert]::ToString([int]$mask, 2)))" -ForegroundColor Green
    return [int]$mask
}

function Disable-WTUCoreIsolation {
    # Full affinity mask
    $totalCores = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
    $mask = [Math]::Pow(2, $totalCores) - 1
    Write-Host "[Process] Core isolation removed (full affinity)" -ForegroundColor Green
    return [int]$mask
}



# --- MODULE: registry.psm1 ---
<#
.SYNOPSIS  Registry CRUD module with backup/restore support.
#>

function Get-WTUReg {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name } catch { return $null }
}

function Set-WTUReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Remove-WTUReg {
    param([string]$Path, [string]$Name)
    Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

function Test-WTURegPath { param([string]$Path); return (Test-Path $Path) }



# --- MODULE: services.psm1 ---
<#
.SYNOPSIS  Service management module with state capture and restoration.
#>

function Get-WTUServiceState {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) { return @{ Status=$svc.Status; StartType=$svc.StartType } }
    return $null
}

function Set-WTUServiceStartup {
    param([string]$Name, [string]$StartupType)
    try { Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop; return $true }
    catch { Write-Warning "Cannot set $Name to $StartupType : $_"; return $false }
}

function Stop-WTUService { param([string]$Name); Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
function Start-WTUService { param([string]$Name); Start-Service -Name $Name -ErrorAction SilentlyContinue }



# --- MODULE: timer.psm1 ---
<#
.SYNOPSIS  Timer resolution control using NtSetTimerResolution via P/Invoke.
           Add-Type is deferred into a function so it is safe when inlined
           by Compile.ps1 â€” the C# here-string is only evaluated at call time.
#>

function Initialize-WTUTimerType {
    if (-not ([System.Management.Automation.PSTypeName]'WTUTimerResolution').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUTimerResolution {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, ref uint CurrentResolution);
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);
}
"@ -ErrorAction SilentlyContinue
    }
}

function Set-WTUTimerResolution {
<#
.SYNOPSIS  Sets system timer resolution.
.PARAMETER ResolutionMs  Target resolution in milliseconds (e.g. 0.5, 1.0, 15.6).
#>
    param([float]$ResolutionMs)
    Initialize-WTUTimerType
    $desired = [uint]($ResolutionMs * 10000)
    $current = [uint]0
    $null    = [WTUTimerResolution]::NtSetTimerResolution($desired, $true, [ref]$current)
    $actualMs = [Math]::Round($current / 10000.0, 2)
    Write-Host "[Timer] Resolution set to ${actualMs}ms (requested ${ResolutionMs}ms)" -ForegroundColor Green
    return $actualMs
}

function Get-WTUTimerResolution {
<#
.SYNOPSIS  Returns current timer resolution in milliseconds.
#>
    Initialize-WTUTimerType
    [uint]$min=0; [uint]$max=0; [uint]$cur=0
    $null = [WTUTimerResolution]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)
    return [Math]::Round($cur / 10000.0, 2)
}



# --- MODULE: winget.psm1 ---
<#
.SYNOPSIS  WinGet and Chocolatey abstraction module.
#>

function Get-WTUPackageManager {
    $wg = $null -ne (Get-Command winget -EA SilentlyContinue)
    $ch = $null -ne (Get-Command choco  -EA SilentlyContinue)
    return @{ WinGet=$wg; Choco=$ch }
}

function Install-WTUApp {
    param([string]$WinGetId, [string]$ChocoId = '')
    $pm = Get-WTUPackageManager
    if ($pm.WinGet -and $WinGetId) {
        winget install --id $WinGetId --silent --accept-package-agreements --accept-source-agreements 2>&1
        return $true
    } elseif ($pm.Choco -and $ChocoId) {
        choco install $ChocoId -y 2>&1
        return $true
    }
    return $false
}

function Uninstall-WTUApp {
    param([string]$WinGetId)
    $pm = Get-WTUPackageManager
    if ($pm.WinGet -and $WinGetId) {
        winget uninstall --id $WinGetId --silent --accept-source-agreements 2>&1
        return $true
    }
    return $false
}



# --- EMBEDDED CONFIGS (Base64-encoded UTF-8) ---
$sync = @{ configs = @{} }
$sync.configs['applications'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJXUEZJbnN0YWxsQ2hyb21lIjogewogICAgIkNvbnRlbnQiOiAgICAgIkdvb2dsZSBDaHJvbWUiLAogICAgIkRlc2NyaXB0aW9uIjogIkZhc3QsIHNlY3VyZSB3ZWIgYnJvd3NlciBmcm9tIEdvb2dsZS4iLAogICAgIkNhdGVnb3J5IjogICAgIkJyb3dzZXJzIiwKICAgICJQYW5lbCI6ICAgICAgICJJbnN0YWxsIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAid2luZ2V0IjogICAgICAiR29vZ2xlLkNocm9tZSIsCiAgICAiY2hvY28iOiAgICAgICAiZ29vZ2xlY2hyb21lIiwKICAgICJMaW5rIjogICAgICAgICJodHRwczovL3d3dy5nb29nbGUuY29tL2Nocm9tZSIKICB9LAogICJXUEZJbnN0YWxsRmlyZWZveCI6IHsKICAgICJDb250ZW50IjogICAgICJNb3ppbGxhIEZpcmVmb3giLAogICAgIkRlc2NyaXB0aW9uIjogIlByaXZhY3ktZm9jdXNlZCBvcGVuLXNvdXJjZSBicm93c2VyLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiQnJvd3NlcnMiLAogICAgIlBhbmVsIjogICAgICAgIkluc3RhbGwiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJ3aW5nZXQiOiAgICAgICJNb3ppbGxhLkZpcmVmb3giLAogICAgImNob2NvIjogICAgICAgImZpcmVmb3giLAogICAgIkxpbmsiOiAgICAgICAgImh0dHBzOi8vd3d3Lm1vemlsbGEub3JnL2ZpcmVmb3giCiAgfSwKICAiV1BGSW5zdGFsbEJyYXZlIjogewogICAgIkNvbnRlbnQiOiAgICAgIkJyYXZlIEJyb3dzZXIiLAogICAgIkRlc2NyaXB0aW9uIjogIlByaXZhY3ktZmlyc3QgYnJvd3NlciB3aXRoIGJ1aWx0LWluIGFkIGJsb2NraW5nLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiQnJvd3NlcnMiLAogICAgIlBhbmVsIjogICAgICAgIkluc3RhbGwiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJ3aW5nZXQiOiAgICAgICJCcmF2ZS5CcmF2ZSIsCiAgICAiY2hvY28iOiAgICAgICAiYnJhdmUiCiAgfSwKICAiV1BGSW5zdGFsbFZTQ29kZSI6IHsKICAgICJDb250ZW50IjogICAgICJWaXN1YWwgU3R1ZGlvIENvZGUiLAogICAgIkRlc2NyaXB0aW9uIjogIkxpZ2h0d2VpZ2h0LCBleHRlbnNpYmxlIGNvZGUgZWRpdG9yIGJ5IE1pY3Jvc29mdC4iLAogICAgIkNhdGVnb3J5IjogICAgIkRldmVsb3BtZW50IiwKICAgICJQYW5lbCI6ICAgICAgICJJbnN0YWxsIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAid2luZ2V0IjogICAgICAiTWljcm9zb2Z0LlZpc3VhbFN0dWRpb0NvZGUiLAogICAgImNob2NvIjogICAgICAgInZzY29kZSIsCiAgICAiTGluayI6ICAgICAgICAiaHR0cHM6Ly9jb2RlLnZpc3VhbHN0dWRpby5jb20iCiAgfSwKICAiV1BGSW5zdGFsbEdpdCI6IHsKICAgICJDb250ZW50IjogICAgICJHaXQgZm9yIFdpbmRvd3MiLAogICAgIkRlc2NyaXB0aW9uIjogIkRpc3RyaWJ1dGVkIHZlcnNpb24gY29udHJvbCBzeXN0ZW0uIiwKICAgICJDYXRlZ29yeSI6ICAgICJEZXZlbG9wbWVudCIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIkdpdC5HaXQiLAogICAgImNob2NvIjogICAgICAgImdpdCIKICB9LAogICJXUEZJbnN0YWxsTm9kZUpTIjogewogICAgIkNvbnRlbnQiOiAgICAgIk5vZGUuanMgTFRTIiwKICAgICJEZXNjcmlwdGlvbiI6ICJKYXZhU2NyaXB0IHJ1bnRpbWUgYnVpbHQgb24gQ2hyb21lJ3MgVjggZW5naW5lLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiRGV2ZWxvcG1lbnQiLAogICAgIlBhbmVsIjogICAgICAgIkluc3RhbGwiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJ3aW5nZXQiOiAgICAgICJPcGVuSlMuTm9kZUpTLkxUUyIsCiAgICAiY2hvY28iOiAgICAgICAibm9kZWpzLWx0cyIKICB9LAogICJXUEZJbnN0YWxsUHl0aG9uIjogewogICAgIkNvbnRlbnQiOiAgICAgIlB5dGhvbiAzIiwKICAgICJEZXNjcmlwdGlvbiI6ICJQeXRob24gcHJvZ3JhbW1pbmcgbGFuZ3VhZ2UgaW50ZXJwcmV0ZXIuIiwKICAgICJDYXRlZ29yeSI6ICAgICJEZXZlbG9wbWVudCIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIlB5dGhvbi5QeXRob24uMyIsCiAgICAiY2hvY28iOiAgICAgICAicHl0aG9uMyIKICB9LAogICJXUEZJbnN0YWxsU3RlYW0iOiB7CiAgICAiQ29udGVudCI6ICAgICAiU3RlYW0iLAogICAgIkRlc2NyaXB0aW9uIjogIlZhbHZlJ3MgZGlnaXRhbCBnYW1lIGRpc3RyaWJ1dGlvbiBwbGF0Zm9ybS4iLAogICAgIkNhdGVnb3J5IjogICAgIkdhbWluZyIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIlZhbHZlLlN0ZWFtIiwKICAgICJjaG9jbyI6ICAgICAgICJzdGVhbSIKICB9LAogICJXUEZJbnN0YWxsRGlzY29yZCI6IHsKICAgICJDb250ZW50IjogICAgICJEaXNjb3JkIiwKICAgICJEZXNjcmlwdGlvbiI6ICJWb2ljZSwgdmlkZW8sIGFuZCB0ZXh0IGNvbW11bmljYXRpb24gZm9yIGdhbWVycy4iLAogICAgIkNhdGVnb3J5IjogICAgIkdhbWluZyIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIkRpc2NvcmQuRGlzY29yZCIsCiAgICAiY2hvY28iOiAgICAgICAiZGlzY29yZCIKICB9LAogICJXUEZJbnN0YWxsRXBpYyI6IHsKICAgICJDb250ZW50IjogICAgICJFcGljIEdhbWVzIExhdW5jaGVyIiwKICAgICJEZXNjcmlwdGlvbiI6ICJFcGljIEdhbWVzIGRpZ2l0YWwgc3RvcmVmcm9udCBhbmQgbGF1bmNoZXIuIiwKICAgICJDYXRlZ29yeSI6ICAgICJHYW1pbmciLAogICAgIlBhbmVsIjogICAgICAgIkluc3RhbGwiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJ3aW5nZXQiOiAgICAgICJFcGljR2FtZXMuRXBpY0dhbWVzTGF1bmNoZXIiLAogICAgImNob2NvIjogICAgICAgImVwaWNnYW1lc2xhdW5jaGVyIgogIH0sCiAgIldQRkluc3RhbGxNU0lBZnRlcmJ1cm5lciI6IHsKICAgICJDb250ZW50IjogICAgICJNU0kgQWZ0ZXJidXJuZXIiLAogICAgIkRlc2NyaXB0aW9uIjogIkdQVSBvdmVyY2xvY2tpbmcgYW5kIG1vbml0b3JpbmcgdXRpbGl0eS4iLAogICAgIkNhdGVnb3J5IjogICAgIkdhbWluZyIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIkd1cnUzRC5BZnRlcmJ1cm5lciIsCiAgICAiY2hvY28iOiAgICAgICAibXNpYWZ0ZXJidXJuZXIiCiAgfSwKICAiV1BGSW5zdGFsbFZMQyI6IHsKICAgICJDb250ZW50IjogICAgICJWTEMgTWVkaWEgUGxheWVyIiwKICAgICJEZXNjcmlwdGlvbiI6ICJGcmVlLCBvcGVuLXNvdXJjZSBjcm9zcy1wbGF0Zm9ybSBtdWx0aW1lZGlhIHBsYXllci4iLAogICAgIkNhdGVnb3J5IjogICAgIk1lZGlhIiwKICAgICJQYW5lbCI6ICAgICAgICJJbnN0YWxsIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAid2luZ2V0IjogICAgICAiVmlkZW9MQU4uVkxDIiwKICAgICJjaG9jbyI6ICAgICAgICJ2bGMiCiAgfSwKICAiV1BGSW5zdGFsbDdaaXAiOiB7CiAgICAiQ29udGVudCI6ICAgICAiNy1aaXAiLAogICAgIkRlc2NyaXB0aW9uIjogIkZyZWUsIGhpZ2gtY29tcHJlc3Npb24gZmlsZSBhcmNoaXZlci4iLAogICAgIkNhdGVnb3J5IjogICAgIlV0aWxpdGllcyIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIjd6aXAuN3ppcCIsCiAgICAiY2hvY28iOiAgICAgICAiN3ppcCIKICB9LAogICJXUEZJbnN0YWxsRXZlcnl0aGluZyI6IHsKICAgICJDb250ZW50IjogICAgICJFdmVyeXRoaW5nIChTZWFyY2gpIiwKICAgICJEZXNjcmlwdGlvbiI6ICJJbnN0YW50IGZpbGUgc2VhcmNoIGZvciBXaW5kb3dzLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiVXRpbGl0aWVzIiwKICAgICJQYW5lbCI6ICAgICAgICJJbnN0YWxsIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAid2luZ2V0IjogICAgICAidm9pZHRvb2xzLkV2ZXJ5dGhpbmciLAogICAgImNob2NvIjogICAgICAgImV2ZXJ5dGhpbmciCiAgfSwKICAiV1BGSW5zdGFsbEhXaU5GTyI6IHsKICAgICJDb250ZW50IjogICAgICJIV2lORk82NCIsCiAgICAiRGVzY3JpcHRpb24iOiAiQ29tcHJlaGVuc2l2ZSBoYXJkd2FyZSBhbmFseXNpcyBhbmQgbW9uaXRvcmluZy4iLAogICAgIkNhdGVnb3J5IjogICAgIlV0aWxpdGllcyIsCiAgICAiUGFuZWwiOiAgICAgICAiSW5zdGFsbCIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIndpbmdldCI6ICAgICAgIlJFQUxpWC5IV2lORk8iLAogICAgImNob2NvIjogICAgICAgImh3aW5mbyIKICB9LAogICJXUEZJbnN0YWxsTlZJRElBQXBwIjogewogICAgIkNvbnRlbnQiOiAgICAgIk5WSURJQSBBcHAiLAogICAgIkRlc2NyaXB0aW9uIjogIk5WSURJQSBkcml2ZXIgYW5kIHNvZnR3YXJlIG1hbmFnZW1lbnQgcGxhdGZvcm0uIiwKICAgICJDYXRlZ29yeSI6ICAgICJVdGlsaXRpZXMiLAogICAgIlBhbmVsIjogICAgICAgIkluc3RhbGwiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJ3aW5nZXQiOiAgICAgICJOdmlkaWEuTnZpZGlhQXBwIiwKICAgICJjaG9jbyI6ICAgICAgICIiCiAgfSwKICAiV1BGSW5zdGFsbEJ1bGtDcmFwVW5pbnN0YWxsZXIiOiB7CiAgICAiQ29udGVudCI6ICAgICAiQnVsayBDcmFwIFVuaW5zdGFsbGVyIiwKICAgICJEZXNjcmlwdGlvbiI6ICJGYXN0LCBmZWF0dXJlLXJpY2ggYXBwIHVuaW5zdGFsbGVyLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiVXRpbGl0aWVzIiwKICAgICJQYW5lbCI6ICAgICAgICJJbnN0YWxsIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAid2luZ2V0IjogICAgICAiS2xvY21hbi5CdWxrQ3JhcFVuaW5zdGFsbGVyIiwKICAgICJjaG9jbyI6ICAgICAgICJidWxrLWNyYXAtdW5pbnN0YWxsZXIiCiAgfQp9Cg==')) | ConvertFrom-Json)
$sync.configs['tweaks'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJXUEZUd2Vha3NUZWxlbWV0cnkiOiB7CiAgICAiQ29udGVudCI6ICAgICAiRGlzYWJsZSBXaW5kb3dzIFRlbGVtZXRyeSIsCiAgICAiRGVzY3JpcHRpb24iOiAiU3RvcHMgZGlhZ25vc3RpYyBkYXRhIGNvbGxlY3Rpb24gc2VudCB0byBNaWNyb3NvZnQuIEltcHJvdmVzIHByaXZhY3kgYW5kIHJlZHVjZXMgYmFja2dyb3VuZCBDUFUvbmV0d29yayB1c2FnZS4iLAogICAgIkNhdGVnb3J5IjogICAgIkVzc2VudGlhbCBUd2Vha3MiLAogICAgIlBhbmVsIjogICAgICAgIlR3ZWFrcyIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkxpbmsiOiAgICAgICAgImh0dHBzOi8vbGVhcm4ubWljcm9zb2Z0LmNvbS9lbi11cy93aW5kb3dzL3ByaXZhY3kvY29uZmlndXJlLXdpbmRvd3MtZGlhZ25vc3RpYy1kYXRhLWluLXlvdXItb3JnYW5pemF0aW9uIiwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU09GVFdBUkVcXFBvbGljaWVzXFxNaWNyb3NvZnRcXFdpbmRvd3NcXERhdGFDb2xsZWN0aW9uIiwgIk5hbWUiOiAiQWxsb3dUZWxlbWV0cnkiLCAiVmFsdWUiOiAiMCIsICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMSIgfQogICAgXSwKICAgICJTZXJ2aWNlIjogWwogICAgICB7ICJOYW1lIjogIkRpYWdUcmFjayIsICAgICAgICAiU3RhcnR1cFR5cGUiOiAiRGlzYWJsZWQiLCAiT3JpZ2luYWxUeXBlIjogIkF1dG9tYXRpYyIgfSwKICAgICAgeyAiTmFtZSI6ICJkbXdhcHB1c2hzZXJ2aWNlIiwgIlN0YXJ0dXBUeXBlIjogIkRpc2FibGVkIiwgIk9yaWdpbmFsVHlwZSI6ICJNYW51YWwiICAgIH0KICAgIF0sCiAgICAiVmFsaWRhdGUiOiB7ICJDb21tYW5kIjogIkdldC1JdGVtUHJvcGVydHlWYWx1ZSAnSEtMTTpcXFNPRlRXQVJFXFxQb2xpY2llc1xcTWljcm9zb2Z0XFxXaW5kb3dzXFxEYXRhQ29sbGVjdGlvbicgQWxsb3dUZWxlbWV0cnkiLCAiRXhwZWN0ZWQiOiAiMCIgfQogIH0sCgogICJXUEZUd2Vha3NEaXNhYmxlQ29ydGFuYSI6IHsKICAgICJDb250ZW50IjogICAgICJEaXNhYmxlIENvcnRhbmEiLAogICAgIkRlc2NyaXB0aW9uIjogIlByZXZlbnRzIENvcnRhbmEgZnJvbSBydW5uaW5nIGluIHRoZSBiYWNrZ3JvdW5kIGFuZCBjb2xsZWN0aW5nIHZvaWNlL3NlYXJjaCBkYXRhLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiRXNzZW50aWFsIFR3ZWFrcyIsCiAgICAiUGFuZWwiOiAgICAgICAiVHdlYWtzIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiUmVnaXN0cnkiOiBbCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxQb2xpY2llc1xcTWljcm9zb2Z0XFxXaW5kb3dzXFxXaW5kb3dzIFNlYXJjaCIsICJOYW1lIjogIkFsbG93Q29ydGFuYSIsICJWYWx1ZSI6ICIwIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIxIiB9CiAgICBdCiAgfSwKCiAgIldQRlR3ZWFrc0Rpc2FibGVTZWFyY2hIaWdobGlnaHRzIjogewogICAgIkNvbnRlbnQiOiAgICAgIkRpc2FibGUgU2VhcmNoIEhpZ2hsaWdodHMiLAogICAgIkRlc2NyaXB0aW9uIjogIlJlbW92ZXMgdHJlbmRpbmcgc2VhcmNoZXMgYW5kIG5ld3MgaGlnaGxpZ2h0cyBmcm9tIHRoZSBTdGFydC9TZWFyY2ggYmFyLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiRXNzZW50aWFsIFR3ZWFrcyIsCiAgICAiUGFuZWwiOiAgICAgICAiVHdlYWtzIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAiUmVnaXN0cnkiOiBbCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3NcXEN1cnJlbnRWZXJzaW9uXFxTZWFyY2hTZXR0aW5ncyIsICJOYW1lIjogIklzRHluYW1pY1NlYXJjaEJveEVuYWJsZWQiLCAiVmFsdWUiOiAiMCIsICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMSIgfQogICAgXQogIH0sCgogICJXUEZUd2Vha3NEaXNhYmxlQWN0aXZpdHlIaXN0b3J5IjogewogICAgIkNvbnRlbnQiOiAgICAgIkRpc2FibGUgQWN0aXZpdHkgSGlzdG9yeSIsCiAgICAiRGVzY3JpcHRpb24iOiAiRGlzYWJsZXMgV2luZG93cyBUaW1lbGluZSBhbmQgYWN0aXZpdHkgdHJhY2tpbmcgc2VudCB0byBNaWNyb3NvZnQuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQcml2YWN5IiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU09GVFdBUkVcXFBvbGljaWVzXFxNaWNyb3NvZnRcXFdpbmRvd3NcXFN5c3RlbSIsICJOYW1lIjogIkVuYWJsZUFjdGl2aXR5RmVlZCIsICAgICJWYWx1ZSI6ICIwIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIxIiB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcUG9saWNpZXNcXE1pY3Jvc29mdFxcV2luZG93c1xcU3lzdGVtIiwgIk5hbWUiOiAiUHVibGlzaFVzZXJBY3Rpdml0aWVzIiwgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjEiIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxQb2xpY2llc1xcTWljcm9zb2Z0XFxXaW5kb3dzXFxTeXN0ZW0iLCAiTmFtZSI6ICJVcGxvYWRVc2VyQWN0aXZpdGllcyIsICAiVmFsdWUiOiAiMCIsICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMSIgfQogICAgXQogIH0sCgogICJXUEZUd2Vha3NEaXNhYmxlTG9jYXRpb25UcmFja2luZyI6IHsKICAgICJDb250ZW50IjogICAgICJEaXNhYmxlIExvY2F0aW9uIFRyYWNraW5nIiwKICAgICJEZXNjcmlwdGlvbiI6ICJUdXJucyBvZmYgbG9jYXRpb24gc2VydmljZXMgc3lzdGVtLXdpZGUuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQcml2YWN5IiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93c1xcQ3VycmVudFZlcnNpb25cXENhcGFiaWxpdHlBY2Nlc3NNYW5hZ2VyXFxDb25zZW50U3RvcmVcXGxvY2F0aW9uIiwgIk5hbWUiOiAiVmFsdWUiLCAiVmFsdWUiOiAiRGVueSIsICJUeXBlIjogIlN0cmluZyIsICJPcmlnaW5hbFZhbHVlIjogIkFsbG93IiB9CiAgICBdCiAgfSwKCiAgIldQRlR3ZWFrc0Rpc2FibGVBZHZlcnRpc2luZ0lEIjogewogICAgIkNvbnRlbnQiOiAgICAgIkRpc2FibGUgQWR2ZXJ0aXNpbmcgSUQiLAogICAgIkRlc2NyaXB0aW9uIjogIlByZXZlbnRzIGFwcHMgZnJvbSB1c2luZyB0aGUgYWR2ZXJ0aXNpbmcgSUQgZm9yIHBlcnNvbmFsaXplZCBhZHMuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQcml2YWN5IiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93c1xcQ3VycmVudFZlcnNpb25cXEFkdmVydGlzaW5nSW5mbyIsICJOYW1lIjogIkVuYWJsZWQiLCAiVmFsdWUiOiAiMCIsICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMSIgfQogICAgXQogIH0sCgogICJXUEZUd2Vha3NWaXN1YWxFZmZlY3RzUGVyZm9ybWFuY2UiOiB7CiAgICAiQ29udGVudCI6ICAgICAiT3B0aW1pemUgVmlzdWFsIEVmZmVjdHMgZm9yIFBlcmZvcm1hbmNlIiwKICAgICJEZXNjcmlwdGlvbiI6ICJEaXNhYmxlcyBhbmltYXRpb25zLCBzaGFkb3dzLCBhbmQgdHJhbnNwYXJlbmN5IGVmZmVjdHMgdG8gcmVkdWNlIENQVS9HUFUgb3ZlcmhlYWQuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQZXJmb3JtYW5jZSIsCiAgICAiUGFuZWwiOiAgICAgICAiVHdlYWtzIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAiUmVnaXN0cnkiOiBbCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3NcXEN1cnJlbnRWZXJzaW9uXFxFeHBsb3JlclxcVmlzdWFsRWZmZWN0cyIsICJOYW1lIjogIlZpc3VhbEZYU2V0dGluZyIsICJWYWx1ZSI6ICIyIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxEZXNrdG9wIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIlVzZXJQcmVmZXJlbmNlc01hc2siLCAiVmFsdWUiOiAiOTAxMjA3ODAxMDAwMDAwMCIsICJUeXBlIjogIkJpbmFyeSIsICJPcmlnaW5hbFZhbHVlIjogbnVsbCB9CiAgICBdLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIlNldC1JdGVtUHJvcGVydHkgJ0hLQ1U6XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzXFxDdXJyZW50VmVyc2lvblxcRXhwbG9yZXJcXFZpc3VhbEVmZmVjdHMnIC1OYW1lIFZpc3VhbEZYU2V0dGluZyAtVmFsdWUgMiAtVHlwZSBEV29yZCIKICAgIF0KICB9LAoKICAiV1BGVHdlYWtzRGlzYWJsZUZhc3RTdGFydHVwIjogewogICAgIkNvbnRlbnQiOiAgICAgIkRpc2FibGUgRmFzdCBTdGFydHVwIiwKICAgICJEZXNjcmlwdGlvbiI6ICJGb3JjZXMgYSBmdWxsIHNodXRkb3duL2Jvb3QgY3ljbGUuIFJlc29sdmVzIGlzc3VlcyB3aXRoIGR1YWwtYm9vdCBhbmQgZW5zdXJlcyBhbGwgZHJpdmVycyBsb2FkIGNsZWFubHkuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQZXJmb3JtYW5jZSIsCiAgICAiUGFuZWwiOiAgICAgICAiVHdlYWtzIiwKICAgICJUeXBlIjogICAgICAgICJDaGVja0JveCIsCiAgICAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiUmVnaXN0cnkiOiBbCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXENvbnRyb2xcXFNlc3Npb24gTWFuYWdlclxcUG93ZXIiLCAiTmFtZSI6ICJIaWJlcmJvb3RFbmFibGVkIiwgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjEiIH0KICAgIF0KICB9LAoKICAiV1BGVHdlYWtzSGlnaFBlcmZvcm1hbmNlUG93ZXIiOiB7CiAgICAiQ29udGVudCI6ICAgICAiU2V0IEhpZ2ggUGVyZm9ybWFuY2UgUG93ZXIgUGxhbiIsCiAgICAiRGVzY3JpcHRpb24iOiAiU3dpdGNoZXMgdG8gdGhlIEhpZ2ggUGVyZm9ybWFuY2UgcG93ZXIgcGxhbiBmb3IgbWF4aW11bSBDUFUgcmVzcG9uc2l2ZW5lc3MuIiwKICAgICJDYXRlZ29yeSI6ICAgICJQZXJmb3JtYW5jZSIsCiAgICAiUGFuZWwiOiAgICAgICAiVHdlYWtzIiwKICAgICJUeXBlIjogICAgICAgICJCdXR0b24iLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgOGM1ZTdmZGEtZThiZi00YTk2LTlhODUtYTZlMjNhOGM2MzVjIgogICAgXSwKICAgICJVbmRvU2NyaXB0IjogWwogICAgICAicG93ZXJjZmcgLXNldGFjdGl2ZSAzODFiNDIyMi1mNjk0LTQxZjAtOTY4NS1mZjViYjI2MGRmMmUiCiAgICBdCiAgfSwKCiAgIldQRlR3ZWFrc1VsdGltYXRlUGVyZm9ybWFuY2VQb3dlciI6IHsKICAgICJDb250ZW50IjogICAgICJTZXQgVWx0aW1hdGUgUGVyZm9ybWFuY2UgUG93ZXIgUGxhbiIsCiAgICAiRGVzY3JpcHRpb24iOiAiVW5sb2NrcyB0aGUgVWx0aW1hdGUgUGVyZm9ybWFuY2UgcG93ZXIgcGxhbiBmb3IgbWluaW11bSBsYXRlbmN5LiBIaWdoZXN0IHBvd2VyIGNvbnN1bXB0aW9uLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiUGVyZm9ybWFuY2UiLAogICAgIlBhbmVsIjogICAgICAgIlR3ZWFrcyIsCiAgICAiVHlwZSI6ICAgICAgICAiQnV0dG9uIiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJXYXJuaW5nIjogICAgICJJbmNyZWFzZXMgcG93ZXIgY29uc3VtcHRpb24gc2lnbmlmaWNhbnRseS4gTm90IHJlY29tbWVuZGVkIGZvciBsYXB0b3BzIG9uIGJhdHRlcnkuIiwKICAgICJJbnZva2VTY3JpcHQiOiBbCiAgICAgICJwb3dlcmNmZyAtZHVwbGljYXRlc2NoZW1lIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIKICAgIF0sCiAgICAiVW5kb1NjcmlwdCI6IFsKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgMzgxYjQyMjItZjY5NC00MWYwLTk2ODUtZmY1YmIyNjBkZjJlIgogICAgXQogIH0sCgogICJXUEZUd2Vha3NEaXNhYmxlV2luZG93c1NlYXJjaCI6IHsKICAgICJDb250ZW50IjogICAgICJEaXNhYmxlIFdpbmRvd3MgU2VhcmNoIEluZGV4aW5nIiwKICAgICJEZXNjcmlwdGlvbiI6ICJTdG9wcyB0aGUgc2VhcmNoIGluZGV4ZXIgc2VydmljZS4gUmVkdWNlcyBkaXNrIEkvTyBhbmQgUkFNLiBVc2UgRXZlcnl0aGluZyBhcHAgaW5zdGVhZC4iLAogICAgIkNhdGVnb3J5IjogICAgIlBlcmZvcm1hbmNlIiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJTZXJ2aWNlIjogWwogICAgICB7ICJOYW1lIjogIldTZWFyY2giLCAiU3RhcnR1cFR5cGUiOiAiRGlzYWJsZWQiLCAiT3JpZ2luYWxUeXBlIjogIkF1dG9tYXRpY0RlbGF5ZWRTdGFydCIgfQogICAgXSwKICAgICJJbnZva2VTY3JpcHQiOiBbCiAgICAgICJTdG9wLVNlcnZpY2UgLU5hbWUgV1NlYXJjaCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUiCiAgICBdCiAgfSwKCiAgIldQRlR3ZWFrc1Nob3dGaWxlRXh0ZW5zaW9ucyI6IHsKICAgICJDb250ZW50IjogICAgICJTaG93IEZpbGUgRXh0ZW5zaW9ucyIsCiAgICAiRGVzY3JpcHRpb24iOiAiRGlzcGxheXMgZmlsZSBleHRlbnNpb25zIGluIEV4cGxvcmVyLiBSZWNvbW1lbmRlZCBmb3Igc2VjdXJpdHkgYXdhcmVuZXNzLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiQWR2YW5jZWQgVHdlYWtzIiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93c1xcQ3VycmVudFZlcnNpb25cXEV4cGxvcmVyXFxBZHZhbmNlZCIsICJOYW1lIjogIkhpZGVGaWxlRXh0IiwgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjEiIH0KICAgIF0KICB9LAoKICAiV1BGVHdlYWtzU2hvd0hpZGRlbkZpbGVzIjogewogICAgIkNvbnRlbnQiOiAgICAgIlNob3cgSGlkZGVuIEZpbGVzIGFuZCBGb2xkZXJzIiwKICAgICJEZXNjcmlwdGlvbiI6ICJSZXZlYWxzIGhpZGRlbiBzeXN0ZW0gZmlsZXMgYW5kIGZvbGRlcnMgaW4gRXhwbG9yZXIuIiwKICAgICJDYXRlZ29yeSI6ICAgICJBZHZhbmNlZCBUd2Vha3MiLAogICAgIlBhbmVsIjogICAgICAgIlR3ZWFrcyIsCiAgICAiVHlwZSI6ICAgICAgICAiQ2hlY2tCb3giLAogICAgIlJlZ2lzdHJ5IjogWwogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzXFxDdXJyZW50VmVyc2lvblxcRXhwbG9yZXJcXEFkdmFuY2VkIiwgIk5hbWUiOiAiSGlkZGVuIiwgIlZhbHVlIjogIjEiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjIiIH0KICAgIF0KICB9LAoKICAiV1BGVHdlYWtzRGlzYWJsZVhib3hHYW1lQmFyIjogewogICAgIkNvbnRlbnQiOiAgICAgIkRpc2FibGUgWGJveCBHYW1lIEJhciIsCiAgICAiRGVzY3JpcHRpb24iOiAiUmVtb3ZlcyB0aGUgWGJveCBvdmVybGF5IHRoYXQgY2FuIGNhdXNlIGlucHV0IGxhZyBhbmQgRlBTIGRyb3BzIGluIGdhbWVzLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiQWR2YW5jZWQgVHdlYWtzIiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93c1xcQ3VycmVudFZlcnNpb25cXEdhbWVEVlIiLCAiTmFtZSI6ICJBcHBDYXB0dXJlRW5hYmxlZCIsICJWYWx1ZSI6ICIwIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIxIiB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTeXN0ZW1cXEdhbWVDb25maWdTdG9yZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIkdhbWVEVlJfRW5hYmxlZCIsICAgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjEiIH0KICAgIF0sCiAgICAiQXBweCI6IFsiTWljcm9zb2Z0Llhib3hHYW1pbmdPdmVybGF5Il0KICB9LAoKICAiV1BGVHdlYWtzTnVtTG9ja09uU3RhcnR1cCI6IHsKICAgICJDb250ZW50IjogICAgICJFbmFibGUgTnVtTG9jayBvbiBTdGFydHVwIiwKICAgICJEZXNjcmlwdGlvbiI6ICJFbnN1cmVzIHRoZSBOdW1Mb2NrIGtleSBpcyBvbiB3aGVuIFdpbmRvd3Mgc3RhcnRzLiIsCiAgICAiQ2F0ZWdvcnkiOiAgICAiQWR2YW5jZWQgVHdlYWtzIiwKICAgICJQYW5lbCI6ICAgICAgICJUd2Vha3MiLAogICAgIlR5cGUiOiAgICAgICAgIkNoZWNrQm94IiwKICAgICJSZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcS2V5Ym9hcmQiLCAiTmFtZSI6ICJJbml0aWFsS2V5Ym9hcmRJbmRpY2F0b3JzIiwgIlZhbHVlIjogIjIiLCAiVHlwZSI6ICJTdHJpbmciLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiB9CiAgICBdCiAgfQp9Cg==')) | ConvertFrom-Json)
$sync.configs['gaming'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJXVEZNb2RlVWx0aW1hdGUiOiB7CiAgICAiQ29udGVudCI6ICJVbHRpbWF0ZSBHYW1pbmcgTW9kZSIsCiAgICAiRGVzY3JpcHRpb24iOiAiTWF4aW11bSBGUFMuIEdQVSBjbG9ja3MgdW5sb2NrZWQgdG8gYm9vc3QsIDEwMCUgVERQLCAwLjVtcyB0aW1lci4gTWF5IHRoZXJtYWwgdGhyb3R0bGUgZHVyaW5nIGxvbmcgc2Vzc2lvbnMuIiwKICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgUGVyZm9ybWFuY2UgTW9kZXMiLAogICAgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJXYXJuaW5nIjogIkhpZ2ggdGVtcGVyYXR1cmVzIGV4cGVjdGVkICg4MC04NUMpLiBOb3QgcmVjb21tZW5kZWQgZm9yIHNlc3Npb25zIGxvbmdlciB0aGFuIDIgaG91cnMuIiwKICAgICJSZXN0YXJ0UmVxdWlyZWQiOiBmYWxzZSwKICAgICJyZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93cyBOVFxcQ3VycmVudFZlcnNpb25cXE11bHRpbWVkaWFcXFN5c3RlbVByb2ZpbGUiLCAiTmFtZSI6ICJTeXN0ZW1SZXNwb25zaXZlbmVzcyIsICJWYWx1ZSI6ICIwIiwgICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMjAiIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3MgTlRcXEN1cnJlbnRWZXJzaW9uXFxNdWx0aW1lZGlhXFxTeXN0ZW1Qcm9maWxlIiwgIk5hbWUiOiAiTm9MYXp5TW9kZSIsICAgICAgICAgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTeXN0ZW1cXEdhbWVDb25maWdTdG9yZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiR2FtZURWUl9GU0VCZWhhdmlvck1vZGUiLCJWYWx1ZSI6ICIyIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzXFxTY2hlZHVsZXIiLCAgICAgICAgICAgICJOYW1lIjogIkRpc2FibGVQcmVlbXB0aW9uIiwgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzXFxEd20iLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiT3ZlcmxheVRlc3RNb2RlIiwgICAgICJWYWx1ZSI6ICI1IiwgICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMCIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXENvbnRyb2xcXEdyYXBoaWNzRHJpdmVycyIsICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJId1NjaE1vZGUiLCAgICAgICAgICAgIlZhbHVlIjogIjEiLCAgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIyIiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIk1vdXNlU3BlZWQiLCAgICAgICAgICAiVmFsdWUiOiAiMCIsICAiVHlwZSI6ICJTdHJpbmciLCJPcmlnaW5hbFZhbHVlIjogIjEiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQxIiwgICAgICJWYWx1ZSI6ICIwIiwgICJUeXBlIjogIlN0cmluZyIsIk9yaWdpbmFsVmFsdWUiOiAiNiIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXENvbnRyb2wgUGFuZWxcXE1vdXNlIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJNb3VzZVRocmVzaG9sZDIiLCAgICAgIlZhbHVlIjogIjAiLCAgIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICIxMCIgfSwKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcU2Vzc2lvbiBNYW5hZ2VyXFxNZW1vcnkgTWFuYWdlbWVudCIsICAgICJOYW1lIjogIkRpc2FibGVQYWdpbmdFeGVjdXRpdmUiLCJWYWx1ZSI6ICIxIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiAgfQogICAgXSwKICAgICJJbnZva2VTY3JpcHQiOiBbCiAgICAgICJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDAuNSIsCiAgICAgICJJbnZva2UtV1RGR1BVQ29udHJvbCAtVmVuZG9yIE5WSURJQSAtVW5sb2NrQ2xvY2tzIC1Qb3dlckxpbWl0UGVyY2VudCAxMDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAyYTczNzQ0MS0xOTMwLTQ0MDItOGQ3Ny1iMmJlYmJhMzA4YTMgNDhlNmI3YTYtNTBmNS00NzgyLWE1ZDQtMWJiYmVkMWUyYWJhIDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdGl2ZSBzY2hlbWVfY3VycmVudCIsCiAgICAgICJwb3dlcmNmZyAtZHVwbGljYXRlc2NoZW1lIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIsCiAgICAgICJTZXQtSXRlbVByb3BlcnR5ICdIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcU2Vzc2lvbiBNYW5hZ2VyXFxQb3dlcicgLU5hbWUgJ0hpYmVyYm9vdEVuYWJsZWQnIC1WYWx1ZSAwIgogICAgXSwKICAgICJVbmRvU2NyaXB0IjogWwogICAgICAiSW52b2tlLVdURlRpbWVyQ29udHJvbCAtUmVzb2x1dGlvbiAxNS42IiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1VbmxvY2tDbG9ja3MgLVBvd2VyTGltaXRQZXJjZW50IDEwMCIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN2YWx1ZWluZGV4IHNjaGVtZV9jdXJyZW50IDJhNzM3NDQxLTE5MzAtNDQwMi04ZDc3LWIyYmViYmEzMDhhMyA0OGU2YjdhNi01MGY1LTQ3ODItYTVkNC0xYmJiZWQxZTJhYmEgMSIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN0aXZlIHNjaGVtZV9jdXJyZW50IiwKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgMzgxYjQyMjItZjY5NC00MWYwLTk2ODUtZmY1YmIyNjBkZjJlIiwKICAgICAgIlNldC1JdGVtUHJvcGVydHkgJ0hLTE06XFxTWVNURU1cXEN1cnJlbnRDb250cm9sU2V0XFxDb250cm9sXFxTZXNzaW9uIE1hbmFnZXJcXFBvd2VyJyAtTmFtZSAnSGliZXJib290RW5hYmxlZCcgLVZhbHVlIDEiCiAgICBdLAogICAgInNlcnZpY2UiOiBbCiAgICAgIHsgIk5hbWUiOiAiRGlhZ1RyYWNrIiwgICAgICAgICAgIlN0YXJ0dXBUeXBlIjogIkRpc2FibGVkIiwgICJPcmlnaW5hbFR5cGUiOiAiQXV0b21hdGljIiB9LAogICAgICB7ICJOYW1lIjogImRtd2FwcHVzaHNlcnZpY2UiLCAgICJTdGFydHVwVHlwZSI6ICJEaXNhYmxlZCIsICAiT3JpZ2luYWxUeXBlIjogIk1hbnVhbCIgICAgfQogICAgXSwKICAgICJFc3RpbWF0ZWRJbXBhY3QiOiB7ICJpbnB1dF9sYWdfbXMiOiAifjEwbXMiLCAidGhlcm1hbF9zdXN0YWluYWJpbGl0eSI6ICI4MC04NUMiLCAic3VzdGFpbmVkXzFwY3RfbG93cyI6ICI4NSUgb2YgYXZnIiwgImJlc3RfZm9yIjogIlNob3J0IHNlc3Npb25zLCBiZW5jaG1hcmsgcnVucyIgfQogIH0sCgogICJXVEZNb2RlQ29tcGV0aXRpdmVTdGFibGUiOiB7CiAgICAiQ29udGVudCI6ICJDb21wZXRpdGl2ZSBTdGFibGUgTW9kZSIsCiAgICAiRGVzY3JpcHRpb24iOiAiSHlicmlkOiBMb3cgaW5wdXQgbGF0ZW5jeSB3aXRoIHRoZXJtYWwgc3RhYmlsaXR5LiBMb2NrZWQgMTgwME1IeiBHUFUgYXQgODAlIFREUCBmb3Igc3VzdGFpbmVkIGNvbXBldGl0aXZlIHBlcmZvcm1hbmNlIHdpdGhvdXQgdGhyb3R0bGluZy4iLAogICAgImNhdGVnb3J5IjogIkdhbWluZyBQZXJmb3JtYW5jZSBNb2RlcyIsCiAgICAiVHlwZSI6ICJCdXR0b24iLAogICAgIldhcm5pbmciOiAiSFBFVCBkaXNhYmxlIHJlcXVpcmVzIHJlc3RhcnQuIEdQVSBjbG9jayBsb2NraW5nIHJlcXVpcmVzIE5WSURJQSBkcml2ZXJzIHdpdGggbnZpZGlhLXNtaS4iLAogICAgIlJlc3RhcnRSZXF1aXJlZCI6IHRydWUsCiAgICAicmVnaXN0cnkiOiBbCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3MgTlRcXEN1cnJlbnRWZXJzaW9uXFxNdWx0aW1lZGlhXFxTeXN0ZW1Qcm9maWxlIiwgIk5hbWUiOiAiU3lzdGVtUmVzcG9uc2l2ZW5lc3MiLCAgIlZhbHVlIjogIjAiLCAgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIyMCIgfSwKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93cyBOVFxcQ3VycmVudFZlcnNpb25cXE11bHRpbWVkaWFcXFN5c3RlbVByb2ZpbGUiLCAiTmFtZSI6ICJOb0xhenlNb2RlIiwgICAgICAgICAgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTeXN0ZW1cXEdhbWVDb25maWdTdG9yZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiR2FtZURWUl9GU0VCZWhhdmlvck1vZGUiLCJWYWx1ZSI6ICIyIiwgICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMCIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXENvbnRyb2xcXEdyYXBoaWNzRHJpdmVyc1xcU2NoZWR1bGVyIiwgICAgICAgICAgICAiTmFtZSI6ICJEaXNhYmxlUHJlZW1wdGlvbiIsICAgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzXFxEd20iLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiT3ZlcmxheVRlc3RNb2RlIiwgICAgICAgIlZhbHVlIjogIjUiLCAgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzIiwgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIkh3U2NoTW9kZSIsICAgICAgICAgICAgICJWYWx1ZSI6ICIxIiwgICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMiIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXENvbnRyb2wgUGFuZWxcXE1vdXNlIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJNb3VzZVNwZWVkIiwgICAgICAgICAgICAiVmFsdWUiOiAiMCIsICAiVHlwZSI6ICJTdHJpbmciLCJPcmlnaW5hbFZhbHVlIjogIjEiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQxIiwgICAgICAgIlZhbHVlIjogIjAiLCAgIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICI2IiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIk1vdXNlVGhyZXNob2xkMiIsICAgICAgICJWYWx1ZSI6ICIwIiwgICJUeXBlIjogIlN0cmluZyIsIk9yaWdpbmFsVmFsdWUiOiAiMTAiIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXENvbnRyb2xcXFNlc3Npb24gTWFuYWdlclxcTWVtb3J5IE1hbmFnZW1lbnQiLCAgICAiTmFtZSI6ICJEaXNhYmxlUGFnaW5nRXhlY3V0aXZlIiwiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9CiAgICBdLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMC41IiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybWNsb2NrIGZhbHNlIiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybXRpY2sgeWVzIiwKICAgICAgImJjZGVkaXQgL3NldCBkaXNhYmxlZHluYW1pY3RpY2sgeWVzIiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1Mb2NrQ2xvY2tzIDE4MDAgLU1lbW9yeUNsb2NrcyA2MDAwIC1Qb3dlckxpbWl0UGVyY2VudCA4MCAtUGVyc2lzdGVuY2VNb2RlIiwKICAgICAgIlNldC1JdGVtUHJvcGVydHkgJ0hLTE06XFxTT0ZUV0FSRVxcTlZJRElBIENvcnBvcmF0aW9uXFxHbG9iYWxcXE52Q3BsQXBpXFxQcm9maWxlcycgLU5hbWUgJ0xvd0xhdGVuY3lNb2RlJyAtVmFsdWUgMSAtRm9yY2UiLAogICAgICAiU2V0LUl0ZW1Qcm9wZXJ0eSAnSEtMTTpcXFNPRlRXQVJFXFxOVklESUEgQ29ycG9yYXRpb25cXEdsb2JhbFxcTnZDcGxBcGlcXFByb2ZpbGVzJyAtTmFtZSAnUG93ZXJNaXplck1vZGUnIC1WYWx1ZSAxIC1Gb3JjZSIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN2YWx1ZWluZGV4IHNjaGVtZV9jdXJyZW50IDJhNzM3NDQxLTE5MzAtNDQwMi04ZDc3LWIyYmViYmEzMDhhMyA0OGU2YjdhNi01MGY1LTQ3ODItYTVkNC0xYmJiZWQxZTJhYmEgMCIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN0aXZlIHNjaGVtZV9jdXJyZW50IiwKICAgICAgInBvd2VyY2ZnIC1kdXBsaWNhdGVzY2hlbWUgZTlhNDJiMDItZDVkZi00NDhkLWFhMDAtMDNmMTQ3NDllYjYxIiwKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgZTlhNDJiMDItZDVkZi00NDhkLWFhMDAtMDNmMTQ3NDllYjYxIiwKICAgICAgIlNldC1JdGVtUHJvcGVydHkgJ0hLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzIE5UXFxDdXJyZW50VmVyc2lvblxcTXVsdGltZWRpYVxcU3lzdGVtUHJvZmlsZVxcVGFza3NcXEdhbWVzJyAtTmFtZSAnUHJpb3JpdHknIC1WYWx1ZSA2IC1Gb3JjZSIsCiAgICAgICJTZXQtSXRlbVByb3BlcnR5ICdIS0xNOlxcU09GVFdBUkVcXE1pY3Jvc29mdFxcV2luZG93cyBOVFxcQ3VycmVudFZlcnNpb25cXE11bHRpbWVkaWFcXFN5c3RlbVByb2ZpbGVcXFRhc2tzXFxHYW1lcycgLU5hbWUgJ1NjaGVkdWxpbmcgQ2F0ZWdvcnknIC1WYWx1ZSAnSGlnaCcgLUZvcmNlIgogICAgXSwKICAgICJVbmRvU2NyaXB0IjogWwogICAgICAiSW52b2tlLVdURlRpbWVyQ29udHJvbCAtUmVzb2x1dGlvbiAxNS42IiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybWNsb2NrIHRydWUiLAogICAgICAiYmNkZWRpdCAvc2V0IHVzZXBsYXRmb3JtdGljayBubyIsCiAgICAgICJiY2RlZGl0IC9zZXQgZGlzYWJsZWR5bmFtaWN0aWNrIG5vIiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1VbmxvY2tDbG9ja3MgLVBvd2VyTGltaXRQZXJjZW50IDEwMCIsCiAgICAgICJSZW1vdmUtSXRlbVByb3BlcnR5ICdIS0xNOlxcU09GVFdBUkVcXE5WSURJQSBDb3Jwb3JhdGlvblxcR2xvYmFsXFxOdkNwbEFwaVxcUHJvZmlsZXMnIC1OYW1lICdMb3dMYXRlbmN5TW9kZScgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUiLAogICAgICAiUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAnSEtMTTpcXFNPRlRXQVJFXFxOVklESUEgQ29ycG9yYXRpb25cXEdsb2JhbFxcTnZDcGxBcGlcXFByb2ZpbGVzJyAtTmFtZSAnUG93ZXJNaXplck1vZGUnIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3ZhbHVlaW5kZXggc2NoZW1lX2N1cnJlbnQgMmE3Mzc0NDEtMTkzMC00NDAyLThkNzctYjJiZWJiYTMwOGEzIDQ4ZTZiN2E2LTUwZjUtNDc4Mi1hNWQ0LTFiYmJlZDFlMmFiYSAxIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3RpdmUgc2NoZW1lX2N1cnJlbnQiLAogICAgICAicG93ZXJjZmcgLXNldGFjdGl2ZSAzODFiNDIyMi1mNjk0LTQxZjAtOTY4NS1mZjViYjI2MGRmMmUiLAogICAgICAiU2V0LUl0ZW1Qcm9wZXJ0eSAnSEtMTTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3MgTlRcXEN1cnJlbnRWZXJzaW9uXFxNdWx0aW1lZGlhXFxTeXN0ZW1Qcm9maWxlXFxUYXNrc1xcR2FtZXMnIC1OYW1lICdQcmlvcml0eScgLVZhbHVlIDIgLUZvcmNlIiwKICAgICAgIlNldC1JdGVtUHJvcGVydHkgJ0hLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzIE5UXFxDdXJyZW50VmVyc2lvblxcTXVsdGltZWRpYVxcU3lzdGVtUHJvZmlsZVxcVGFza3NcXEdhbWVzJyAtTmFtZSAnU2NoZWR1bGluZyBDYXRlZ29yeScgLVZhbHVlICdNZWRpdW0nIC1Gb3JjZSIKICAgIF0sCiAgICAic2VydmljZSI6IFsKICAgICAgeyAiTmFtZSI6ICJEaWFnVHJhY2siLCAgICAgICAgICAiU3RhcnR1cFR5cGUiOiAiRGlzYWJsZWQiLCAgICAgICAgICAgICAgICJPcmlnaW5hbFR5cGUiOiAiQXV0b21hdGljIiAgfSwKICAgICAgeyAiTmFtZSI6ICJkbXdhcHB1c2hzZXJ2aWNlIiwgICAiU3RhcnR1cFR5cGUiOiAiRGlzYWJsZWQiLCAgICAgICAgICAgICAgICJPcmlnaW5hbFR5cGUiOiAiTWFudWFsIiAgICAgfSwKICAgICAgeyAiTmFtZSI6ICJXU2VhcmNoIiwgICAgICAgICAgICAiU3RhcnR1cFR5cGUiOiAiQXV0b21hdGljRGVsYXllZFN0YXJ0IiwgICJPcmlnaW5hbFR5cGUiOiAiQXV0b21hdGljIiAgfQogICAgXSwKICAgICJFc3RpbWF0ZWRJbXBhY3QiOiB7ICJpbnB1dF9sYWdfbXMiOiAifjdtcyIsICJmcmFtZV9jb25zaXN0ZW5jeSI6ICIrNDAtNTAlIiwgInRoZXJtYWxfc3VzdGFpbmFiaWxpdHkiOiAiNzAtNzVDIiwgInBlYWtfZnBzX2ltcGFjdCI6ICItOC0xMiUgdnMgVWx0aW1hdGUiLCAic3VzdGFpbmVkXzFwY3RfbG93cyI6ICI5NSUgb2YgYXZnIiwgImJlc3RfZm9yIjogIkNvbXBldGl0aXZlIGdhbWluZyAzKyBob3VycywgbGFwdG9wIGVzcG9ydHMsIHN1bW1lciBnYW1pbmcsIDE0NEh6LTI0MEh6IG1vbml0b3JzIiB9CiAgfSwKCiAgIldURk1vZGVMYXRlbmN5IjogewogICAgIkNvbnRlbnQiOiAiTGF0ZW5jeSAmIFNtb290aG5lc3MiLAogICAgIkRlc2NyaXB0aW9uIjogIk1pbmltdW0gcG9zc2libGUgaW5wdXQgbGFnLiBVbmxvY2tlZCBHUFUgY2xvY2tzLCBhbGwgbGF0ZW5jeSBwaXBlbGluZSB0d2Vha3MuIE1heSB0aGVybWFsIHRocm90dGxlIHVuZGVyIHN1c3RhaW5lZCBsb2FkLiIsCiAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIFBlcmZvcm1hbmNlIE1vZGVzIiwKICAgICJUeXBlIjogIkJ1dHRvbiIsCiAgICAiV2FybmluZyI6ICJIaWdoZXN0IHRlbXBlcmF0dXJlcyBleHBlY3RlZC4gTW9uaXRvciBmb3IgdGhlcm1hbCB0aHJvdHRsaW5nLiIsCiAgICAiUmVzdGFydFJlcXVpcmVkIjogdHJ1ZSwKICAgICJyZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzXFxTY2hlZHVsZXIiLCAiTmFtZSI6ICJEaXNhYmxlUHJlZW1wdGlvbiIsICAiVmFsdWUiOiAiMSIsICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMCIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3NcXER3bSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiT3ZlcmxheVRlc3RNb2RlIiwgICAgIlZhbHVlIjogIjUiLCAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTWVNURU1cXEN1cnJlbnRDb250cm9sU2V0XFxDb250cm9sXFxHcmFwaGljc0RyaXZlcnMiLCAgICAgICAgICAgICJOYW1lIjogIkh3U2NoTW9kZSIsICAgICAgICAgICJWYWx1ZSI6ICIxIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIyIiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJNb3VzZVNwZWVkIiwgICAgICAgICAiVmFsdWUiOiAiMCIsICJUeXBlIjogIlN0cmluZyIsIk9yaWdpbmFsVmFsdWUiOiAiMSIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXENvbnRyb2wgUGFuZWxcXE1vdXNlIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQxIiwgICAgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJTdHJpbmciLCJPcmlnaW5hbFZhbHVlIjogIjYiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIk1vdXNlVGhyZXNob2xkMiIsICAgICJWYWx1ZSI6ICIwIiwgIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICIxMCIgfQogICAgXSwKICAgICJJbnZva2VTY3JpcHQiOiBbCiAgICAgICJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDAuNSIsCiAgICAgICJiY2RlZGl0IC9zZXQgdXNlcGxhdGZvcm1jbG9jayBmYWxzZSIsCiAgICAgICJiY2RlZGl0IC9zZXQgdXNlcGxhdGZvcm10aWNrIHllcyIsCiAgICAgICJiY2RlZGl0IC9zZXQgZGlzYWJsZWR5bmFtaWN0aWNrIHllcyIsCiAgICAgICJJbnZva2UtV1RGR1BVQ29udHJvbCAtVmVuZG9yIE5WSURJQSAtVW5sb2NrQ2xvY2tzIC1Qb3dlckxpbWl0UGVyY2VudCAxMDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAyYTczNzQ0MS0xOTMwLTQ0MDItOGQ3Ny1iMmJlYmJhMzA4YTMgNDhlNmI3YTYtNTBmNS00NzgyLWE1ZDQtMWJiYmVkMWUyYWJhIDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdGl2ZSBzY2hlbWVfY3VycmVudCIsCiAgICAgICJwb3dlcmNmZyAtZHVwbGljYXRlc2NoZW1lIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIKICAgIF0sCiAgICAiVW5kb1NjcmlwdCI6IFsKICAgICAgIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMTUuNiIsCiAgICAgICJiY2RlZGl0IC9zZXQgdXNlcGxhdGZvcm1jbG9jayB0cnVlIiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybXRpY2sgbm8iLAogICAgICAiYmNkZWRpdCAvc2V0IGRpc2FibGVkeW5hbWljdGljayBubyIsCiAgICAgICJJbnZva2UtV1RGR1BVQ29udHJvbCAtVmVuZG9yIE5WSURJQSAtVW5sb2NrQ2xvY2tzIC1Qb3dlckxpbWl0UGVyY2VudCAxMDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAyYTczNzQ0MS0xOTMwLTQ0MDItOGQ3Ny1iMmJlYmJhMzA4YTMgNDhlNmI3YTYtNTBmNS00NzgyLWE1ZDQtMWJiYmVkMWUyYWJhIDEiLAogICAgICAicG93ZXJjZmcgL3NldGFjdGl2ZSBzY2hlbWVfY3VycmVudCIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIDM4MWI0MjIyLWY2OTQtNDFmMC05Njg1LWZmNWJiMjYwZGYyZSIKICAgIF0sCiAgICAiRXN0aW1hdGVkSW1wYWN0IjogeyAiaW5wdXRfbGFnX21zIjogIn42bXMiLCAiZnJhbWVfdmFyaWFuY2UiOiAiTG93IChtYXkgdGhyb3R0bGUpIiwgInRoZXJtYWxfc3VzdGFpbmFiaWxpdHkiOiAiODAtODVDIiwgInBlYWtfZnBzIjogIk1heGltdW0iLCAic3VzdGFpbmVkXzFwY3RfbG93cyI6ICI5MCUgb2YgYXZnIiwgImJlc3RfZm9yIjogIlB1cmUgbGF0ZW5jeSwgc2hvcnQgbWF0Y2hlcywgYWltIHRyYWluaW5nIiB9CiAgfSwKCiAgIldURk1vZGVFc3BvcnRzIjogewogICAgIkNvbnRlbnQiOiAiQ29tcGV0aXRpdmUgRXNwb3J0cyIsCiAgICAiRGVzY3JpcHRpb24iOiAiVG91cm5hbWVudC1yZWFkeS4gVGltZXIgKyBDb3JlIGlzb2xhdGlvbiArIE5ldHdvcmsgcHJpb3JpdHkgKyBBbGwgbGF0ZW5jeSB0d2Vha3MuIiwKICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgUGVyZm9ybWFuY2UgTW9kZXMiLAogICAgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJXYXJuaW5nIjogIkNvcmUgaXNvbGF0aW9uIG1heSBhZmZlY3QgYmFja2dyb3VuZCB0YXNrcy4gVXNlIG9ubHkgZHVyaW5nIGNvbXBldGl0aXZlIHBsYXkuIiwKICAgICJSZXN0YXJ0UmVxdWlyZWQiOiB0cnVlLAogICAgInJlZ2lzdHJ5IjogWwogICAgICB7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzIE5UXFxDdXJyZW50VmVyc2lvblxcTXVsdGltZWRpYVxcU3lzdGVtUHJvZmlsZSIsICJOYW1lIjogIlN5c3RlbVJlc3BvbnNpdmVuZXNzIiwgICAiVmFsdWUiOiAiMCIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjIwIiB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzIE5UXFxDdXJyZW50VmVyc2lvblxcTXVsdGltZWRpYVxcU3lzdGVtUHJvZmlsZSIsICJOYW1lIjogIk5vTGF6eU1vZGUiLCAgICAgICAgICAgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTeXN0ZW1cXEdhbWVDb25maWdTdG9yZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiR2FtZURWUl9GU0VCZWhhdmlvck1vZGUiLCAiVmFsdWUiOiAiMiIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjAiICB9LAogICAgICB7ICJQYXRoIjogIkhLTE06XFxTWVNURU1cXEN1cnJlbnRDb250cm9sU2V0XFxDb250cm9sXFxHcmFwaGljc0RyaXZlcnNcXFNjaGVkdWxlciIsICAgICAgICAgICAgIk5hbWUiOiAiRGlzYWJsZVByZWVtcHRpb24iLCAgICAgICJWYWx1ZSI6ICIxIiwgICJUeXBlIjogIkRXb3JkIiwgIk9yaWdpbmFsVmFsdWUiOiAiMCIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtMTTpcXFNPRlRXQVJFXFxNaWNyb3NvZnRcXFdpbmRvd3NcXER3bSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJPdmVybGF5VGVzdE1vZGUiLCAgICAgICAgIlZhbHVlIjogIjUiLCAgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzIiwgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIkh3U2NoTW9kZSIsICAgICAgICAgICAgICAiVmFsdWUiOiAiMSIsICAiVHlwZSI6ICJEV29yZCIsICJPcmlnaW5hbFZhbHVlIjogIjIiICB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiTW91c2VTcGVlZCIsICAgICAgICAgICAgICJWYWx1ZSI6ICIwIiwgICJUeXBlIjogIlN0cmluZyIsIk9yaWdpbmFsVmFsdWUiOiAiMSIgIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXENvbnRyb2wgUGFuZWxcXE1vdXNlIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJNb3VzZVRocmVzaG9sZDEiLCAgICAgICAgIlZhbHVlIjogIjAiLCAgIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICI2IiAgfSwKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIk1vdXNlVGhyZXNob2xkMiIsICAgICAgICAiVmFsdWUiOiAiMCIsICAiVHlwZSI6ICJTdHJpbmciLCJPcmlnaW5hbFZhbHVlIjogIjEwIiB9CiAgICBdLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMC41IiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybWNsb2NrIGZhbHNlIiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybXRpY2sgeWVzIiwKICAgICAgImJjZGVkaXQgL3NldCBkaXNhYmxlZHluYW1pY3RpY2sgeWVzIiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1Mb2NrQ2xvY2tzIDE4MDAgLU1lbW9yeUNsb2NrcyA2MDAwIC1Qb3dlckxpbWl0UGVyY2VudCA4NSAtUGVyc2lzdGVuY2VNb2RlIiwKICAgICAgIkludm9rZS1XVEZOZXR3b3JrR2FtaW5nIC1BY3Rpb24gT3B0aW1pemUiLAogICAgICAiSW52b2tlLVdURlByb2Nlc3NPcHRpbWl6ZSAtQ29yZUlzb2xhdGlvbiAtR2FtZVByaW9yaXR5IEhpZ2giLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAyYTczNzQ0MS0xOTMwLTQ0MDItOGQ3Ny1iMmJlYmJhMzA4YTMgNDhlNmI3YTYtNTBmNS00NzgyLWE1ZDQtMWJiYmVkMWUyYWJhIDAiLAogICAgICAicG93ZXJjZmcgL3NldGFjdGl2ZSBzY2hlbWVfY3VycmVudCIsCiAgICAgICJwb3dlcmNmZyAtZHVwbGljYXRlc2NoZW1lIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIGU5YTQyYjAyLWQ1ZGYtNDQ4ZC1hYTAwLTAzZjE0NzQ5ZWI2MSIKICAgIF0sCiAgICAiVW5kb1NjcmlwdCI6IFsKICAgICAgIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMTUuNiIsCiAgICAgICJiY2RlZGl0IC9zZXQgdXNlcGxhdGZvcm1jbG9jayB0cnVlIiwKICAgICAgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybXRpY2sgbm8iLAogICAgICAiYmNkZWRpdCAvc2V0IGRpc2FibGVkeW5hbWljdGljayBubyIsCiAgICAgICJJbnZva2UtV1RGR1BVQ29udHJvbCAtVmVuZG9yIE5WSURJQSAtVW5sb2NrQ2xvY2tzIC1Qb3dlckxpbWl0UGVyY2VudCAxMDAiLAogICAgICAiSW52b2tlLVdURk5ldHdvcmtHYW1pbmcgLUFjdGlvbiBSZXN0b3JlIiwKICAgICAgIkludm9rZS1XVEZQcm9jZXNzT3B0aW1pemUgLUNvcmVJc29sYXRpb25PZmYgLUdhbWVQcmlvcml0eSBOb3JtYWwiLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAyYTczNzQ0MS0xOTMwLTQ0MDItOGQ3Ny1iMmJlYmJhMzA4YTMgNDhlNmI3YTYtNTBmNS00NzgyLWE1ZDQtMWJiYmVkMWUyYWJhIDEiLAogICAgICAicG93ZXJjZmcgL3NldGFjdGl2ZSBzY2hlbWVfY3VycmVudCIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIDM4MWI0MjIyLWY2OTQtNDFmMC05Njg1LWZmNWJiMjYwZGYyZSIKICAgIF0sCiAgICAiRXN0aW1hdGVkSW1wYWN0IjogeyAiaW5wdXRfbGFnX21zIjogIn42LjVtcyIsICJmcmFtZV92YXJpYW5jZSI6ICJOZWFyIFplcm8iLCAidGhlcm1hbF9zdXN0YWluYWJpbGl0eSI6ICI3Mi03N0MiLCAicGVha19mcHMiOiAiSGlnaCIsICJzdXN0YWluZWRfMXBjdF9sb3dzIjogIjkzJSBvZiBhdmciLCAiYmVzdF9mb3IiOiAiVG91cm5hbWVudHMsIHJhbmtlZCBwbGF5LCBzY3JpbXMiIH0KICB9LAoKICAiV1RGTW9kZVN0YWJsZSI6IHsKICAgICJDb250ZW50IjogIlN0YWJsZSBQZXJmb3JtYW5jZSIsCiAgICAiRGVzY3JpcHRpb24iOiAiSGlnaGVzdCBjb25zaXN0ZW5jeSB3aXRoIGxvd2VzdCB0ZW1wZXJhdHVyZXMuIExvY2tlZCAxNTAwTUh6IEdQVSBhdCA3MCUgVERQLiBCZXN0IGZvciB0aGVybWFsLWNvbnN0cmFpbmVkIHN5c3RlbXMuIiwKICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgUGVyZm9ybWFuY2UgTW9kZXMiLAogICAgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJXYXJuaW5nIjogIlNpZ25pZmljYW50bHkgbG93ZXIgcGVhayBGUFMuIFVzZSBvbmx5IGlmIHRoZXJtYWwgdGhyb3R0bGluZyBpcyBzZXZlcmUuIiwKICAgICJSZXN0YXJ0UmVxdWlyZWQiOiBmYWxzZSwKICAgICJyZWdpc3RyeSI6IFsKICAgICAgeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzXFxTY2hlZHVsZXIiLCAiTmFtZSI6ICJEaXNhYmxlUHJlZW1wdGlvbiIsICJWYWx1ZSI6ICIxIiwgIlR5cGUiOiAiRFdvcmQiLCAiT3JpZ2luYWxWYWx1ZSI6ICIwIiB9LAogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJOYW1lIjogIk1vdXNlU3BlZWQiLCAgICAgICAgIlZhbHVlIjogIjAiLCAiVHlwZSI6ICJTdHJpbmciLCJPcmlnaW5hbFZhbHVlIjogIjEiIH0sCiAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXENvbnRyb2wgUGFuZWxcXE1vdXNlIiwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQxIiwgICAiVmFsdWUiOiAiMCIsICJUeXBlIjogIlN0cmluZyIsIk9yaWdpbmFsVmFsdWUiOiAiNiIgfSwKICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiTmFtZSI6ICJNb3VzZVRocmVzaG9sZDIiLCAgICJWYWx1ZSI6ICIwIiwgIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICIxMCJ9CiAgICBdLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMS4wIiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1Mb2NrQ2xvY2tzIDE1MDAgLU1lbW9yeUNsb2NrcyA1MDAwIC1Qb3dlckxpbWl0UGVyY2VudCA3MCAtUGVyc2lzdGVuY2VNb2RlIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3ZhbHVlaW5kZXggc2NoZW1lX2N1cnJlbnQgMmE3Mzc0NDEtMTkzMC00NDAyLThkNzctYjJiZWJiYTMwOGEzIDQ4ZTZiN2E2LTUwZjUtNDc4Mi1hNWQ0LTFiYmJlZDFlMmFiYSAxIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3RpdmUgc2NoZW1lX2N1cnJlbnQiLAogICAgICAicG93ZXJjZmcgLXNldGFjdGl2ZSAzODFiNDIyMi1mNjk0LTQxZjAtOTY4NS1mZjViYjI2MGRmMmUiCiAgICBdLAogICAgIlVuZG9TY3JpcHQiOiBbCiAgICAgICJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDE1LjYiLAogICAgICAiSW52b2tlLVdURkdQVUNvbnRyb2wgLVZlbmRvciBOVklESUEgLVVubG9ja0Nsb2NrcyAtUG93ZXJMaW1pdFBlcmNlbnQgMTAwIiwKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgMzgxYjQyMjItZjY5NC00MWYwLTk2ODUtZmY1YmIyNjBkZjJlIgogICAgXSwKICAgICJFc3RpbWF0ZWRJbXBhY3QiOiB7ICJpbnB1dF9sYWdfbXMiOiAifjEybXMiLCAiZnJhbWVfdmFyaWFuY2UiOiAiTmVhciBaZXJvIiwgInRoZXJtYWxfc3VzdGFpbmFiaWxpdHkiOiAiNjUtNzBDIiwgInBlYWtfZnBzIjogIlJlZHVjZWQiLCAic3VzdGFpbmVkXzFwY3RfbG93cyI6ICI5OCUgb2YgYXZnIiwgImJlc3RfZm9yIjogIlRoZXJtYWwgaXNzdWVzLCBub2lzZS1zZW5zaXRpdmUsIEhUUEMsIHN1bW1lciBnYW1pbmciIH0KICB9LAoKICAiV1RGTW9kZUxhcHRvcCI6IHsKICAgICJDb250ZW50IjogIkxhcHRvcCBCYWxhbmNlZCIsCiAgICAiRGVzY3JpcHRpb24iOiAiQWRhcHRpdmUgcGVyZm9ybWFuY2UgYmFzZWQgb24gcG93ZXIgc291cmNlLiBBQzogTWF4IHBlcmZvcm1hbmNlLiBEQzogQmF0dGVyeSBlZmZpY2llbnQuIiwKICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgUGVyZm9ybWFuY2UgTW9kZXMiLAogICAgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJXYXJuaW5nIjogIkF1dG9tYXRpY2FsbHkgc3dpdGNoZXMgcHJvZmlsZXMgd2hlbiBBQy9EQyBjaGFuZ2VzLiIsCiAgICAiUmVzdGFydFJlcXVpcmVkIjogZmFsc2UsCiAgICAiSW52b2tlU2NyaXB0IjogWwogICAgICAiSW52b2tlLVdURlRpbWVyQ29udHJvbCAtUmVzb2x1dGlvbiAxLjAiLAogICAgICAiSW52b2tlLVdURkdQVUNvbnRyb2wgLVZlbmRvciBOVklESUEgLUFkYXB0aXZlUG93ZXIiLAogICAgICAicG93ZXJjZmcgLWR1cGxpY2F0ZXNjaGVtZSBlOWE0MmIwMi1kNWRmLTQ0OGQtYWEwMC0wM2YxNDc0OWViNjEiLAogICAgICAicG93ZXJjZmcgL3NldGFjdmFsdWVpbmRleCBzY2hlbWVfY3VycmVudCAzODFiNDIyMi1mNjk0LTQxZjAtOTY4NS1mZjViYjI2MGRmMmUgMjM4YzlmYTgtMGFhZC00MWVkLTgzZjQtOTdiZTI0MmM4ZjIwIDI1ZDAwYTk4LTZkOGQtNGFlZS04ZjRiLTljNWY0ZTVlM2Y0ZSAxIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3RpdmUgc2NoZW1lX2N1cnJlbnQiCiAgICBdLAogICAgIlVuZG9TY3JpcHQiOiBbCiAgICAgICJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDE1LjYiLAogICAgICAiSW52b2tlLVdURkdQVUNvbnRyb2wgLVZlbmRvciBOVklESUEgLVVubG9ja0Nsb2NrcyAtUG93ZXJMaW1pdFBlcmNlbnQgMTAwIiwKICAgICAgInBvd2VyY2ZnIC1zZXRhY3RpdmUgMzgxYjQyMjItZjY5NC00MWYwLTk2ODUtZmY1YmIyNjBkZjJlIgogICAgXSwKICAgICJFc3RpbWF0ZWRJbXBhY3QiOiB7ICJpbnB1dF9sYWdfbXMiOiAifjEybXMgKEFDKSAvIH4xOG1zIChEQykiLCAiZnJhbWVfdmFyaWFuY2UiOiAiTG93IiwgInRoZXJtYWxfc3VzdGFpbmFiaWxpdHkiOiAiQWRhcHRpdmUiLCAicGVha19mcHMiOiAiQWRhcHRpdmUiLCAic3VzdGFpbmVkXzFwY3RfbG93cyI6ICJBZGFwdGl2ZSIsICJiZXN0X2ZvciI6ICJEYWlseSBsYXB0b3AgdXNlLCBBQy9EQyBzd2l0Y2hpbmciIH0KICB9LAoKICAiV1RGTW9kZUJhdHRlcnkiOiB7CiAgICAiQ29udGVudCI6ICJCYXR0ZXJ5IFNhdmVyIiwKICAgICJEZXNjcmlwdGlvbiI6ICJNYXhpbXVtIGJhdHRlcnkgbGlmZSB3aXRoIG1pbmltYWwgcGVyZm9ybWFuY2UuIEZvciB0cmF2ZWwgYW5kIHVucGx1Z2dlZCB1c2Ugb25seS4iLAogICAgImNhdGVnb3J5IjogIkdhbWluZyBQZXJmb3JtYW5jZSBNb2RlcyIsCiAgICAiVHlwZSI6ICJCdXR0b24iLAogICAgIldhcm5pbmciOiAiU2V2ZXJlbHkgcmVkdWNlZCBnYW1pbmcgcGVyZm9ybWFuY2UuIE5vdCByZWNvbW1lbmRlZCBmb3IgY29tcGV0aXRpdmUgcGxheS4iLAogICAgIlJlc3RhcnRSZXF1aXJlZCI6IGZhbHNlLAogICAgInJlZ2lzdHJ5IjogWwogICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsICJOYW1lIjogIk1vdXNlU3BlZWQiLCAiVmFsdWUiOiAiMSIsICJUeXBlIjogIlN0cmluZyIsICJPcmlnaW5hbFZhbHVlIjogIjEiIH0KICAgIF0sCiAgICAiSW52b2tlU2NyaXB0IjogWwogICAgICAiSW52b2tlLVdURlRpbWVyQ29udHJvbCAtUmVzb2x1dGlvbiAxNS42IiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1Qb3dlclNhdmVNb2RlIiwKICAgICAgInBvd2VyY2ZnIC9zZXRhY3ZhbHVlaW5kZXggc2NoZW1lX2N1cnJlbnQgMzgxYjQyMjItZjY5NC00MWYwLTk2ODUtZmY1YmIyNjBkZjJlIDIzOGM5ZmE4LTBhYWQtNDFlZC04M2Y0LTk3YmUyNDJjOGYyMCAyNWQwMGE5OC02ZDhkLTRhZWUtOGY0Yi05YzVmNGU1ZTNmNGUgMiIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN0aXZlIHNjaGVtZV9jdXJyZW50IiwKICAgICAgInBvd2VyY2ZnIC9zZXRkY3ZhbHVlaW5kZXggc2NoZW1lX2N1cnJlbnQgc3ViX3Byb2Nlc3NvciBQUk9DVEhST1RUTEVNSU4gNSIsCiAgICAgICJwb3dlcmNmZyAvc2V0YWN0aXZlIHNjaGVtZV9jdXJyZW50IgogICAgXSwKICAgICJVbmRvU2NyaXB0IjogWwogICAgICAiSW52b2tlLVdURlRpbWVyQ29udHJvbCAtUmVzb2x1dGlvbiAxNS42IiwKICAgICAgIkludm9rZS1XVEZHUFVDb250cm9sIC1WZW5kb3IgTlZJRElBIC1VbmxvY2tDbG9ja3MgLVBvd2VyTGltaXRQZXJjZW50IDEwMCIsCiAgICAgICJwb3dlcmNmZyAtc2V0YWN0aXZlIDM4MWI0MjIyLWY2OTQtNDFmMC05Njg1LWZmNWJiMjYwZGYyZSIKICAgIF0sCiAgICAiRXN0aW1hdGVkSW1wYWN0IjogeyAiaW5wdXRfbGFnX21zIjogIn4yNW1zIiwgImZyYW1lX3ZhcmlhbmNlIjogIkxvdyIsICJ0aGVybWFsX3N1c3RhaW5hYmlsaXR5IjogIkNvb2wiLCAicGVha19mcHMiOiAiTWluaW1hbCIsICJzdXN0YWluZWRfMXBjdF9sb3dzIjogIk4vQSIsICJiZXN0X2ZvciI6ICJNYXhpbXVtIGJhdHRlcnkgbGlmZSwgdHJhdmVsLCBub24tZ2FtaW5nIHRhc2tzIiB9CiAgfSwKCiAgIldURlR3ZWFrc1RpbWVyTWF4IjogICAgICAgICAgeyAiQ29udGVudCI6ICJUaW1lciBSZXNvbHV0aW9uOiAwLjVtcyIsICAgICAgICAgICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgSW5kaXZpZHVhbCBUd2Vha3MiLCAiVHlwZSI6ICJDaGVja0JveCIsICJJbnZva2VTY3JpcHQiOiBbIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMC41Il0sICAgICAgICAgICAgICAgICAgICAgICAgIlVuZG9TY3JpcHQiOiBbIkludm9rZS1XVEZUaW1lckNvbnRyb2wgLVJlc29sdXRpb24gMTUuNiJdIH0sCiAgIldURlR3ZWFrc1RpbWVyMW1zIjogICAgICAgICAgIHsgIkNvbnRlbnQiOiAiVGltZXIgUmVzb2x1dGlvbjogMS4wbXMiLCAgICAgICAgICAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIEluZGl2aWR1YWwgVHdlYWtzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLCAiSW52b2tlU2NyaXB0IjogWyJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDEuMCJdLCAgICAgICAgICAgICAgICAgICAgICAgICJVbmRvU2NyaXB0IjogWyJJbnZva2UtV1RGVGltZXJDb250cm9sIC1SZXNvbHV0aW9uIDE1LjYiXSB9LAogICJXVEZUd2Vha3NIUEVURGlzYWJsZSI6ICAgICAgICB7ICJDb250ZW50IjogIkRpc2FibGUgSFBFVCIsICAgICAgICAgICAgICAgICAgICAgICAgImNhdGVnb3J5IjogIkdhbWluZyBJbmRpdmlkdWFsIFR3ZWFrcyIsICJUeXBlIjogIkNoZWNrQm94IiwgIlJlc3RhcnRSZXF1aXJlZCI6IHRydWUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJJbnZva2VTY3JpcHQiOiBbImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybWNsb2NrIGZhbHNlIiwiYmNkZWRpdCAvc2V0IHVzZXBsYXRmb3JtdGljayB5ZXMiLCJiY2RlZGl0IC9zZXQgZGlzYWJsZWR5bmFtaWN0aWNrIHllcyJdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiVW5kb1NjcmlwdCI6ICAgWyJiY2RlZGl0IC9zZXQgdXNlcGxhdGZvcm1jbG9jayB0cnVlIiwgImJjZGVkaXQgL3NldCB1c2VwbGF0Zm9ybXRpY2sgbm8iLCAiYmNkZWRpdCAvc2V0IGRpc2FibGVkeW5hbWljdGljayBubyJdIH0sCiAgIldURlR3ZWFrc0Rpc2FibGVQcmVlbXB0aW9uIjogIHsgIkNvbnRlbnQiOiAiRGlzYWJsZSBHUFUgUHJlZW1wdGlvbiIsICAgICAgICAgICAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIEluZGl2aWR1YWwgVHdlYWtzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAicmVnaXN0cnkiOiBbeyAiUGF0aCI6ICJIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcQ29udHJvbFxcR3JhcGhpY3NEcml2ZXJzXFxTY2hlZHVsZXIiLCJOYW1lIjogIkRpc2FibGVQcmVlbXB0aW9uIiwiVmFsdWUiOiAiMSIsIlR5cGUiOiAiRFdvcmQiLCJPcmlnaW5hbFZhbHVlIjogIjAiIH1dIH0sCiAgIldURlR3ZWFrc0Rpc2FibGVNUE8iOiAgICAgICAgIHsgIkNvbnRlbnQiOiAiRGlzYWJsZSBNdWx0aXBsYW5lIE92ZXJsYXkgKE1QTykiLCAgICJjYXRlZ29yeSI6ICJHYW1pbmcgSW5kaXZpZHVhbCBUd2Vha3MiLCAiVHlwZSI6ICJDaGVja0JveCIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJyZWdpc3RyeSI6IFt7ICJQYXRoIjogIkhLTE06XFxTT0ZUV0FSRVxcTWljcm9zb2Z0XFxXaW5kb3dzXFxEd20iLCJOYW1lIjogIk92ZXJsYXlUZXN0TW9kZSIsIlZhbHVlIjogIjUiLCJUeXBlIjogIkRXb3JkIiwiT3JpZ2luYWxWYWx1ZSI6ICIwIiB9XSB9LAogICJXVEZUd2Vha3NEaXNhYmxlSEFHUyI6ICAgICAgICB7ICJDb250ZW50IjogIkRpc2FibGUgSGFyZHdhcmUtQWNjZWxlcmF0ZWQgR1BVIFNjaGVkdWxpbmciLCJjYXRlZ29yeSI6ICJHYW1pbmcgSW5kaXZpZHVhbCBUd2Vha3MiLCJUeXBlIjogIkNoZWNrQm94IiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInJlZ2lzdHJ5IjogW3sgIlBhdGgiOiAiSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXENvbnRyb2xcXEdyYXBoaWNzRHJpdmVycyIsIk5hbWUiOiAiSHdTY2hNb2RlIiwiVmFsdWUiOiAiMSIsIlR5cGUiOiAiRFdvcmQiLCJPcmlnaW5hbFZhbHVlIjogIjIiIH1dIH0sCiAgIldURlR3ZWFrc1Jhd0lucHV0IjogICAgICAgICAgIHsgIkNvbnRlbnQiOiAiRGlzYWJsZSBNb3VzZSBBY2NlbGVyYXRpb24iLCAgICAgICAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIEluZGl2aWR1YWwgVHdlYWtzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAicmVnaXN0cnkiOiBbCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcQ29udHJvbCBQYW5lbFxcTW91c2UiLCJOYW1lIjogIk1vdXNlU3BlZWQiLCAgICAiVmFsdWUiOiAiMCIsIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICIxIiAgfSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQxIiwiVmFsdWUiOiAiMCIsIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICI2IiAgfSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB7ICJQYXRoIjogIkhLQ1U6XFxDb250cm9sIFBhbmVsXFxNb3VzZSIsIk5hbWUiOiAiTW91c2VUaHJlc2hvbGQyIiwiVmFsdWUiOiAiMCIsIlR5cGUiOiAiU3RyaW5nIiwiT3JpZ2luYWxWYWx1ZSI6ICIxMCIgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBdIH0sCiAgIldURlR3ZWFrc0Rpc2FibGVHYW1lRFZSIjogICAgIHsgIkNvbnRlbnQiOiAiRGlzYWJsZSBHYW1lIERWUiAvIFhib3ggR2FtZSBCYXIiLCAgICJjYXRlZ29yeSI6ICJHYW1pbmcgSW5kaXZpZHVhbCBUd2Vha3MiLCAiVHlwZSI6ICJDaGVja0JveCIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJyZWdpc3RyeSI6IFsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB7ICJQYXRoIjogIkhLQ1U6XFxTeXN0ZW1cXEdhbWVDb25maWdTdG9yZSIsIk5hbWUiOiAiR2FtZURWUl9GU0VCZWhhdmlvck1vZGUiLCAgICAgICAgICAgICAgIlZhbHVlIjogIjIiLCJUeXBlIjogIkRXb3JkIiwiT3JpZ2luYWxWYWx1ZSI6ICIwIiB9LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHsgIlBhdGgiOiAiSEtDVTpcXFN5c3RlbVxcR2FtZUNvbmZpZ1N0b3JlIiwiTmFtZSI6ICJHYW1lRFZSX0hvbm9yVXNlckZTRUJlaGF2aW9yTW9kZSIsICAgICAiVmFsdWUiOiAiMSIsIlR5cGUiOiAiRFdvcmQiLCJPcmlnaW5hbFZhbHVlIjogIjAiIH0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgeyAiUGF0aCI6ICJIS0NVOlxcU3lzdGVtXFxHYW1lQ29uZmlnU3RvcmUiLCJOYW1lIjogIkdhbWVEVlJfRFhHSUhvbm9yRlNFV2luZG93c0NvbXBhdGlibGUiLCJWYWx1ZSI6ICIxIiwiVHlwZSI6ICJEV29yZCIsIk9yaWdpbmFsVmFsdWUiOiAiMCIgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiSW52b2tlU2NyaXB0IjogWyJHZXQtQXBweFBhY2thZ2UgTWljcm9zb2Z0Llhib3hHYW1pbmdPdmVybGF5IHwgUmVtb3ZlLUFwcHhQYWNrYWdlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIiwiR2V0LUFwcHhQYWNrYWdlIE1pY3Jvc29mdC5YYm94QXBwIHwgUmVtb3ZlLUFwcHhQYWNrYWdlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIl0gfSwKICAiV1RGVHdlYWtzTmV0d29ya0dhbWluZyI6ICAgICAgeyAiQ29udGVudCI6ICJPcHRpbWl6ZSBUQ1AvSVAgZm9yIEdhbWluZyIsICAgICAgICAgImNhdGVnb3J5IjogIkdhbWluZyBJbmRpdmlkdWFsIFR3ZWFrcyIsICJUeXBlIjogIkNoZWNrQm94IiwgIkludm9rZVNjcmlwdCI6IFsiSW52b2tlLVdURk5ldHdvcmtHYW1pbmcgLUFjdGlvbiBPcHRpbWl6ZSJdLCAiVW5kb1NjcmlwdCI6IFsiSW52b2tlLVdURk5ldHdvcmtHYW1pbmcgLUFjdGlvbiBSZXN0b3JlIl0gfSwKICAiV1RGVHdlYWtzQ29yZUlzb2xhdGlvbiI6ICAgICAgeyAiQ29udGVudCI6ICJDUFUgQ29yZSBJc29sYXRpb24gZm9yIEdhbWluZyIsICAgICAgImNhdGVnb3J5IjogIkdhbWluZyBJbmRpdmlkdWFsIFR3ZWFrcyIsICJUeXBlIjogIkNoZWNrQm94IiwgIkludm9rZVNjcmlwdCI6IFsiSW52b2tlLVdURlByb2Nlc3NPcHRpbWl6ZSAtQ29yZUlzb2xhdGlvbiAtR2FtZVByaW9yaXR5IEhpZ2giXSwgIlVuZG9TY3JpcHQiOiBbIkludm9rZS1XVEZQcm9jZXNzT3B0aW1pemUgLUNvcmVJc29sYXRpb25PZmYgLUdhbWVQcmlvcml0eSBOb3JtYWwiXSB9LAogICJXVEZUd2Vha3NNZW1vcnlPcHRpbWl6ZSI6ICAgICB7ICJDb250ZW50IjogIlJBTSBDbGVhbnVwICYgU3RhbmRieSBMaXN0IiwgICAgICAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIEluZGl2aWR1YWwgVHdlYWtzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLCAiSW52b2tlU2NyaXB0IjogWyJJbnZva2UtV1RGTWVtb3J5T3B0aW1pemUgLUFjdGlvbiBDbGVhbiJdIH0sCiAgIldURlR3ZWFrc1VTQlBvbGxSYXRlIjogICAgICAgIHsgIkNvbnRlbnQiOiAiVVNCIFBvbGwgUmF0ZSBPcHRpbWl6YXRpb24iLCAgICAgICAgICAiY2F0ZWdvcnkiOiAiR2FtaW5nIEluZGl2aWR1YWwgVHdlYWtzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiSW52b2tlU2NyaXB0IjogWyJTZXQtSXRlbVByb3BlcnR5ICdIS0xNOlxcU1lTVEVNXFxDdXJyZW50Q29udHJvbFNldFxcU2VydmljZXNcXHVzYmh1YlxcUGFyYW1ldGVycycgLU5hbWUgJ1BvbGxSYXRlJyAtVmFsdWUgMSAtVHlwZSBEV29yZCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUiXSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIlVuZG9TY3JpcHQiOiAgIFsiUmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAnSEtMTTpcXFNZU1RFTVxcQ3VycmVudENvbnRyb2xTZXRcXFNlcnZpY2VzXFx1c2JodWJcXFBhcmFtZXRlcnMnIC1OYW1lICdQb2xsUmF0ZScgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIl0gfSwKCiAgIldURkNoZWNrcG9pbnRDcmVhdGUiOiAgeyAiQ29udGVudCI6ICJDcmVhdGUgQ2hlY2twb2ludCIsICAiY2F0ZWdvcnkiOiAiR2FtaW5nIFNhZmV0eSIsICJUeXBlIjogIkJ1dHRvbiIsICJJbnZva2VTY3JpcHQiOiBbIkludm9rZS1XVEZDaGVja3BvaW50IC1BY3Rpb24gQ3JlYXRlIC1OYW1lICdNYW51YWwgQ2hlY2twb2ludCciXSB9LAogICJXVEZDaGVja3BvaW50UmVzdG9yZSI6IHsgIkNvbnRlbnQiOiAiUmVzdG9yZSBDaGVja3BvaW50IiwgImNhdGVnb3J5IjogIkdhbWluZyBTYWZldHkiLCAiVHlwZSI6ICJCdXR0b24iLCAiSW52b2tlU2NyaXB0IjogWyJJbnZva2UtV1RGQ2hlY2twb2ludCAtQWN0aW9uIFJlc3RvcmUgLUludGVyYWN0aXZlIl0gfSwKICAiV1RGQ2hlY2twb2ludExpc3QiOiAgICB7ICJDb250ZW50IjogIkxpc3QgQ2hlY2twb2ludHMiLCAgICJjYXRlZ29yeSI6ICJHYW1pbmcgU2FmZXR5IiwgIlR5cGUiOiAiQnV0dG9uIiwgIkludm9rZVNjcmlwdCI6IFsiSW52b2tlLVdURkNoZWNrcG9pbnQgLUFjdGlvbiBMaXN0Il0gfSwKICAiV1RGQ2hlY2twb2ludERlbGV0ZSI6ICB7ICJDb250ZW50IjogIkRlbGV0ZSBDaGVja3BvaW50IiwgICJjYXRlZ29yeSI6ICJHYW1pbmcgU2FmZXR5IiwgIlR5cGUiOiAiQnV0dG9uIiwgIkludm9rZVNjcmlwdCI6IFsiSW52b2tlLVdURkNoZWNrcG9pbnQgLUFjdGlvbiBEZWxldGUgLUludGVyYWN0aXZlIl0gfSwKCiAgIldURk1vbml0b3IiOiAgICB7ICJDb250ZW50IjogIkxhdW5jaCBSZWFsLXRpbWUgTW9uaXRvciIsICJjYXRlZ29yeSI6ICJHYW1pbmcgVG9vbHMiLCAiVHlwZSI6ICJCdXR0b24iLCAiSW52b2tlU2NyaXB0IjogWyJJbnZva2UtV1RGTW9uaXRvciJdIH0sCiAgIldURkJlbmNobWFyayI6ICB7ICJDb250ZW50IjogIlJ1biBCZW5jaG1hcmsiLCAgICAgICAgICAgICJjYXRlZ29yeSI6ICJHYW1pbmcgVG9vbHMiLCAiVHlwZSI6ICJCdXR0b24iLCAiSW52b2tlU2NyaXB0IjogWyJJbnZva2UtV1RGQmVuY2htYXJrIl0gfQp9Cg==')) | ConvertFrom-Json)
$sync.configs['features'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJXUEZGZWF0dXJlV1NMIjogewogICAgIkNvbnRlbnQiOiAiV2luZG93cyBTdWJzeXN0ZW0gZm9yIExpbnV4IChXU0wpIiwKICAgICJEZXNjcmlwdGlvbiI6ICJSdW4gTGludXggZGlzdHJpYnV0aW9ucyBvbiBXaW5kb3dzLiBSZXF1aXJlcyByZXN0YXJ0LiIsCiAgICAiQ2F0ZWdvcnkiOiAiRGV2ZWxvcGVyIEZlYXR1cmVzIiwgIlBhbmVsIjogIkZlYXR1cmVzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgIlJlc3RhcnRSZXF1aXJlZCI6IHRydWUsICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJJbnZva2VTY3JpcHQiOiBbIndzbCAtLWluc3RhbGwgLS1uby1kaXN0cmlidXRpb24iXSwKICAgICJVbmRvU2NyaXB0IjogWyJEaXNhYmxlLVdpbmRvd3NPcHRpb25hbEZlYXR1cmUgLU9ubGluZSAtRmVhdHVyZU5hbWUgTWljcm9zb2Z0LVdpbmRvd3MtU3Vic3lzdGVtLUxpbnV4IC1Ob1Jlc3RhcnQiXQogIH0sCiAgIldQRkZlYXR1cmVIeXBlclYiOiB7CiAgICAiQ29udGVudCI6ICJIeXBlci1WIiwKICAgICJEZXNjcmlwdGlvbiI6ICJCdWlsdC1pbiBUeXBlLTEgaHlwZXJ2aXNvciBmb3IgdmlydHVhbCBtYWNoaW5lcy4gUmVxdWlyZXMgcmVzdGFydC4iLAogICAgIkNhdGVnb3J5IjogIkRldmVsb3BlciBGZWF0dXJlcyIsICJQYW5lbCI6ICJGZWF0dXJlcyIsICJUeXBlIjogIkNoZWNrQm94IiwKICAgICJSZXN0YXJ0UmVxdWlyZWQiOiB0cnVlLCAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiV2FybmluZyI6ICJNYXkgYWZmZWN0IFZNd2FyZS9WaXJ0dWFsQm94IHBlcmZvcm1hbmNlLiIsCiAgICAiSW52b2tlU2NyaXB0IjogWyJFbmFibGUtV2luZG93c09wdGlvbmFsRmVhdHVyZSAtT25saW5lIC1GZWF0dXJlTmFtZSBNaWNyb3NvZnQtSHlwZXItVi1BbGwgLUFsbCAtTm9SZXN0YXJ0Il0sCiAgICAiVW5kb1NjcmlwdCI6IFsiRGlzYWJsZS1XaW5kb3dzT3B0aW9uYWxGZWF0dXJlIC1PbmxpbmUgLUZlYXR1cmVOYW1lIE1pY3Jvc29mdC1IeXBlci1WLUFsbCAtTm9SZXN0YXJ0Il0KICB9LAogICJXUEZGZWF0dXJlU2FuZGJveCI6IHsKICAgICJDb250ZW50IjogIldpbmRvd3MgU2FuZGJveCIsCiAgICAiRGVzY3JpcHRpb24iOiAiSXNvbGF0ZWQgZGVza3RvcCBlbnZpcm9ubWVudCB0byBzYWZlbHkgcnVuIHVudHJ1c3RlZCBhcHBzLiBSZXF1aXJlcyByZXN0YXJ0LiIsCiAgICAiQ2F0ZWdvcnkiOiAiRGV2ZWxvcGVyIEZlYXR1cmVzIiwgIlBhbmVsIjogIkZlYXR1cmVzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgIlJlc3RhcnRSZXF1aXJlZCI6IHRydWUsICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJJbnZva2VTY3JpcHQiOiBbIkVuYWJsZS1XaW5kb3dzT3B0aW9uYWxGZWF0dXJlIC1PbmxpbmUgLUZlYXR1cmVOYW1lIENvbnRhaW5lcnMtRGlzcG9zYWJsZUNsaWVudFZNIC1BbGwgLU5vUmVzdGFydCJdLAogICAgIlVuZG9TY3JpcHQiOiBbIkRpc2FibGUtV2luZG93c09wdGlvbmFsRmVhdHVyZSAtT25saW5lIC1GZWF0dXJlTmFtZSBDb250YWluZXJzLURpc3Bvc2FibGVDbGllbnRWTSAtTm9SZXN0YXJ0Il0KICB9LAogICJXUEZGZWF0dXJlRG90TmV0MzUiOiB7CiAgICAiQ29udGVudCI6ICIuTkVUIEZyYW1ld29yayAzLjUiLAogICAgIkRlc2NyaXB0aW9uIjogIkxlZ2FjeSAuTkVUIHJ1bnRpbWUgcmVxdWlyZWQgYnkgbWFueSBvbGRlciBnYW1lcyBhbmQgYXBwcy4iLAogICAgIkNhdGVnb3J5IjogIlJ1bnRpbWUgRnJhbWV3b3JrcyIsICJQYW5lbCI6ICJGZWF0dXJlcyIsICJUeXBlIjogIkNoZWNrQm94IiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJJbnZva2VTY3JpcHQiOiBbIkVuYWJsZS1XaW5kb3dzT3B0aW9uYWxGZWF0dXJlIC1PbmxpbmUgLUZlYXR1cmVOYW1lIE5ldEZ4MyAtQWxsIl0sCiAgICAiVW5kb1NjcmlwdCI6IFsiRGlzYWJsZS1XaW5kb3dzT3B0aW9uYWxGZWF0dXJlIC1PbmxpbmUgLUZlYXR1cmVOYW1lIE5ldEZ4MyAtTm9SZXN0YXJ0Il0KICB9LAogICJXUEZGZWF0dXJlVGVsbmV0IjogewogICAgIkNvbnRlbnQiOiAiVGVsbmV0IENsaWVudCIsCiAgICAiRGVzY3JpcHRpb24iOiAiTGVnYWN5IFRlbG5ldCBjbGllbnQgZm9yIG5ldHdvcmsgZGlhZ25vc3RpY3MuIiwKICAgICJDYXRlZ29yeSI6ICJOZXR3b3JrIEZlYXR1cmVzIiwgIlBhbmVsIjogIkZlYXR1cmVzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsiRW5hYmxlLVdpbmRvd3NPcHRpb25hbEZlYXR1cmUgLU9ubGluZSAtRmVhdHVyZU5hbWUgVGVsbmV0Q2xpZW50IC1Ob1Jlc3RhcnQiXSwKICAgICJVbmRvU2NyaXB0IjogWyJEaXNhYmxlLVdpbmRvd3NPcHRpb25hbEZlYXR1cmUgLU9ubGluZSAtRmVhdHVyZU5hbWUgVGVsbmV0Q2xpZW50IC1Ob1Jlc3RhcnQiXQogIH0sCiAgIldQRkZlYXR1cmVTU0hDbGllbnQiOiB7CiAgICAiQ29udGVudCI6ICJPcGVuU1NIIENsaWVudCIsCiAgICAiRGVzY3JpcHRpb24iOiAiQnVpbHQtaW4gT3BlblNTSCBjbGllbnQgZm9yIHJlbW90ZSBhY2Nlc3MuIiwKICAgICJDYXRlZ29yeSI6ICJOZXR3b3JrIEZlYXR1cmVzIiwgIlBhbmVsIjogIkZlYXR1cmVzIiwgIlR5cGUiOiAiQ2hlY2tCb3giLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsiQWRkLVdpbmRvd3NDYXBhYmlsaXR5IC1PbmxpbmUgLU5hbWUgT3BlblNTSC5DbGllbnR+fn5+MC4wLjEuMCJdLAogICAgIlVuZG9TY3JpcHQiOiBbIlJlbW92ZS1XaW5kb3dzQ2FwYWJpbGl0eSAtT25saW5lIC1OYW1lIE9wZW5TU0guQ2xpZW50fn5+fjAuMC4xLjAiXQogIH0sCiAgIldQRkZlYXR1cmVEaXJlY3RQbGF5IjogewogICAgIkNvbnRlbnQiOiAiRGlyZWN0UGxheSAoTGVnYWN5IEdhbWVzKSIsCiAgICAiRGVzY3JpcHRpb24iOiAiRW5hYmxlcyBEaXJlY3RQbGF5IGZvciBvbGQgZ2FtZXMgdGhhdCByZXF1aXJlIGl0LiIsCiAgICAiQ2F0ZWdvcnkiOiAiR2FtaW5nIENvbXBhdGliaWxpdHkiLCAiUGFuZWwiOiAiRmVhdHVyZXMiLCAiVHlwZSI6ICJDaGVja0JveCIsCiAgICAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiSW52b2tlU2NyaXB0IjogWyJFbmFibGUtV2luZG93c09wdGlvbmFsRmVhdHVyZSAtT25saW5lIC1GZWF0dXJlTmFtZSBEaXJlY3RQbGF5IC1BbGwgLU5vUmVzdGFydCJdLAogICAgIlVuZG9TY3JpcHQiOiBbIkRpc2FibGUtV2luZG93c09wdGlvbmFsRmVhdHVyZSAtT25saW5lIC1GZWF0dXJlTmFtZSBEaXJlY3RQbGF5IC1Ob1Jlc3RhcnQiXQogIH0KfQo=')) | ConvertFrom-Json)
$sync.configs['repairs'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJXVFVSZXBhaXJXaW5kb3dzVXBkYXRlIjogewogICAgIkNvbnRlbnQiOiAiUmVzZXQgV2luZG93cyBVcGRhdGUiLAogICAgIkRlc2NyaXB0aW9uIjogIlN0b3BzIHVwZGF0ZSBzZXJ2aWNlcywgcmVuYW1lcyBTb2Z0d2FyZURpc3RyaWJ1dGlvbiBhbmQgQ2F0cm9vdDIsIHRoZW4gcmVzdGFydHMgc2VydmljZXMuIEZpeGVzIHN0dWNrIG9yIGJyb2tlbiBXaW5kb3dzIFVwZGF0ZS4iLAogICAgIkNhdGVnb3J5IjogIldpbmRvd3MgVXBkYXRlIiwgIlBhbmVsIjogIlJlcGFpciIsICJUeXBlIjogIkJ1dHRvbiIsCiAgICAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiSW52b2tlU2NyaXB0IjogWwogICAgICAiU3RvcC1TZXJ2aWNlIC1OYW1lIHd1YXVzZXJ2LGNyeXB0U3ZjLGJpdHMsbXNpc2VydmVyIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSIsCiAgICAgICJSZW5hbWUtSXRlbSAnJGVudjpTeXN0ZW1Sb290XFxTb2Z0d2FyZURpc3RyaWJ1dGlvbicgJ1NvZnR3YXJlRGlzdHJpYnV0aW9uLm9sZCcgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUiLAogICAgICAiUmVuYW1lLUl0ZW0gJyRlbnY6U3lzdGVtUm9vdFxcU3lzdGVtMzJcXGNhdHJvb3QyJyAnY2F0cm9vdDIub2xkJyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSIsCiAgICAgICJTdGFydC1TZXJ2aWNlIC1OYW1lIHd1YXVzZXJ2LGNyeXB0U3ZjLGJpdHMsbXNpc2VydmVyIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIiwKICAgICAgIldyaXRlLUhvc3QgJ1tPS10gV2luZG93cyBVcGRhdGUgcmVzZXQgY29tcGxldGUuJyAtRm9yZWdyb3VuZENvbG9yIEdyZWVuIgogICAgXQogIH0sCiAgIldUVVJlcGFpck5ldHdvcmsiOiB7CiAgICAiQ29udGVudCI6ICJSZXNldCBOZXR3b3JrIFN0YWNrIiwKICAgICJEZXNjcmlwdGlvbiI6ICJSZXNldHMgV2luc29jaywgVENQL0lQIHN0YWNrLCBETlMgY2FjaGUsIGFuZCBmaXJld2FsbCB0byBkZWZhdWx0cy4gRml4ZXMgY29tbW9uIG5ldHdvcmsgY29ubmVjdGl2aXR5IGlzc3Vlcy4iLAogICAgIkNhdGVnb3J5IjogIk5ldHdvcmsiLCAiUGFuZWwiOiAiUmVwYWlyIiwgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJSZXN0YXJ0UmVxdWlyZWQiOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIm5ldHNoIHdpbnNvY2sgcmVzZXQiLAogICAgICAibmV0c2ggaW50IGlwIHJlc2V0IiwKICAgICAgImlwY29uZmlnIC9yZWxlYXNlIiwKICAgICAgImlwY29uZmlnIC9yZW5ldyIsCiAgICAgICJpcGNvbmZpZyAvZmx1c2hkbnMiLAogICAgICAibmV0c2ggYWR2ZmlyZXdhbGwgcmVzZXQiLAogICAgICAiV3JpdGUtSG9zdCAnW09LXSBOZXR3b3JrIHN0YWNrIHJlc2V0LiBSZXN0YXJ0IHJlcXVpcmVkLicgLUZvcmVncm91bmRDb2xvciBHcmVlbiIKICAgIF0KICB9LAogICJXVFVSZXBhaXJTRkMiOiB7CiAgICAiQ29udGVudCI6ICJTeXN0ZW0gRmlsZSBDaGVja2VyIChzZmMgL3NjYW5ub3cpIiwKICAgICJEZXNjcmlwdGlvbiI6ICJTY2FucyBhbmQgcmVwYWlycyBjb3JydXB0ZWQgV2luZG93cyBzeXN0ZW0gZmlsZXMuIiwKICAgICJDYXRlZ29yeSI6ICJTeXN0ZW0gRmlsZXMiLCAiUGFuZWwiOiAiUmVwYWlyIiwgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJSZXF1aXJlc0FkbWluIjogdHJ1ZSwKICAgICJJbnZva2VTY3JpcHQiOiBbCiAgICAgICJzZmMgL3NjYW5ub3ciLAogICAgICAiV3JpdGUtSG9zdCAnW09LXSBTRkMgc2NhbiBjb21wbGV0ZS4gQ2hlY2sgb3V0cHV0IGFib3ZlIGZvciBkZXRhaWxzLicgLUZvcmVncm91bmRDb2xvciBHcmVlbiIKICAgIF0KICB9LAogICJXVFVSZXBhaXJESVNNIjogewogICAgIkNvbnRlbnQiOiAiRElTTSBSZXN0b3JlSGVhbHRoIiwKICAgICJEZXNjcmlwdGlvbiI6ICJVc2VzIERJU00gdG8gcmVwYWlyIHRoZSBXaW5kb3dzIGNvbXBvbmVudCBzdG9yZS4gUnVuIGFmdGVyIFNGQyBpZiBpc3N1ZXMgcGVyc2lzdC4iLAogICAgIkNhdGVnb3J5IjogIlN5c3RlbSBGaWxlcyIsICJQYW5lbCI6ICJSZXBhaXIiLCAiVHlwZSI6ICJCdXR0b24iLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIkRJU00gL09ubGluZSAvQ2xlYW51cC1JbWFnZSAvQ2hlY2tIZWFsdGgiLAogICAgICAiRElTTSAvT25saW5lIC9DbGVhbnVwLUltYWdlIC9TY2FuSGVhbHRoIiwKICAgICAgIkRJU00gL09ubGluZSAvQ2xlYW51cC1JbWFnZSAvUmVzdG9yZUhlYWx0aCIsCiAgICAgICJXcml0ZS1Ib3N0ICdbT0tdIERJU00gUmVzdG9yZUhlYWx0aCBjb21wbGV0ZS4nIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4iCiAgICBdCiAgfSwKICAiV1RVUmVwYWlyQ29tcG9uZW50Q2xlYW51cCI6IHsKICAgICJDb250ZW50IjogIkNvbXBvbmVudCBTdG9yZSBDbGVhbnVwIiwKICAgICJEZXNjcmlwdGlvbiI6ICJSZW1vdmVzIHN1cGVyc2VkZWQgY29tcG9uZW50cyBmcm9tIFdpblN4UywgZnJlZWluZyBkaXNrIHNwYWNlLiIsCiAgICAiQ2F0ZWdvcnkiOiAiRGlzayBDbGVhbnVwIiwgIlBhbmVsIjogIlJlcGFpciIsICJUeXBlIjogIkJ1dHRvbiIsCiAgICAiUmVxdWlyZXNBZG1pbiI6IHRydWUsCiAgICAiV2FybmluZyI6ICJUaGlzIG9wZXJhdGlvbiBpcyBpcnJldmVyc2libGUuIFN1cGVyc2VkZWQgY29tcG9uZW50cyBjYW5ub3QgYmUgdW5pbnN0YWxsZWQgYWZ0ZXIgY2xlYW51cC4iLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIkRJU00gL09ubGluZSAvQ2xlYW51cC1JbWFnZSAvU3RhcnRDb21wb25lbnRDbGVhbnVwIC9SZXNldEJhc2UiLAogICAgICAiV3JpdGUtSG9zdCAnW09LXSBDb21wb25lbnQgc3RvcmUgY2xlYW51cCBjb21wbGV0ZS4nIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4iCiAgICBdCiAgfSwKICAiV1RVUmVwYWlyRE5TRmx1c2giOiB7CiAgICAiQ29udGVudCI6ICJGbHVzaCBETlMgQ2FjaGUiLAogICAgIkRlc2NyaXB0aW9uIjogIkNsZWFycyB0aGUgRE5TIHJlc29sdmVyIGNhY2hlLiBGaXhlcyBuYW1lIHJlc29sdXRpb24gaXNzdWVzLiIsCiAgICAiQ2F0ZWdvcnkiOiAiTmV0d29yayIsICJQYW5lbCI6ICJSZXBhaXIiLCAiVHlwZSI6ICJCdXR0b24iLAogICAgIlJlcXVpcmVzQWRtaW4iOiBmYWxzZSwKICAgICJJbnZva2VTY3JpcHQiOiBbImlwY29uZmlnIC9mbHVzaGRucyIsICJXcml0ZS1Ib3N0ICdbT0tdIEROUyBjYWNoZSBmbHVzaGVkLicgLUZvcmVncm91bmRDb2xvciBHcmVlbiJdCiAgfSwKICAiV1RVUmVwYWlyVGVtcENsZWFuIjogewogICAgIkNvbnRlbnQiOiAiQ2xlYW4gVGVtcCBGb2xkZXJzIiwKICAgICJEZXNjcmlwdGlvbiI6ICJSZW1vdmVzIGZpbGVzIGZyb20gJVRFTVAlLCBXaW5kb3dzXFxUZW1wLCBhbmQgUHJlZmV0Y2ggZm9sZGVycy4iLAogICAgIkNhdGVnb3J5IjogIkRpc2sgQ2xlYW51cCIsICJQYW5lbCI6ICJSZXBhaXIiLCAiVHlwZSI6ICJCdXR0b24iLAogICAgIlJlcXVpcmVzQWRtaW4iOiB0cnVlLAogICAgIkludm9rZVNjcmlwdCI6IFsKICAgICAgIlJlbW92ZS1JdGVtIC1QYXRoICckZW52OlRFTVBcXConIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSIsCiAgICAgICJSZW1vdmUtSXRlbSAtUGF0aCAnJGVudjpTeXN0ZW1Sb290XFxUZW1wXFwqJyAtUmVjdXJzZSAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUiLAogICAgICAiUmVtb3ZlLUl0ZW0gLVBhdGggJyRlbnY6U3lzdGVtUm9vdFxcUHJlZmV0Y2hcXConIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSIsCiAgICAgICJXcml0ZS1Ib3N0ICdbT0tdIFRlbXAgZm9sZGVycyBjbGVhbmVkLicgLUZvcmVncm91bmRDb2xvciBHcmVlbiIKICAgIF0KICB9Cn0K')) | ConvertFrom-Json)
$sync.configs['dns'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJEZWZhdWx0REhDUCI6IHsKICAgICJDb250ZW50IjogIkRlZmF1bHQgKERIQ1ApIiwKICAgICJEZXNjcmlwdGlvbiI6ICJVc2UgRE5TIHNlcnZlcnMgcHJvdmlkZWQgYXV0b21hdGljYWxseSBieSB5b3VyIElTUCBvciByb3V0ZXIuIiwKICAgICJDYXRlZ29yeSI6ICJETlMgUHJvdmlkZXJzIiwgIlBhbmVsIjogIkNvbmZpZyIsICJUeXBlIjogIkJ1dHRvbiIsCiAgICAiSVB2NFByaW1hcnkiOiAiIiwgIklQdjRTZWNvbmRhcnkiOiAiIiwKICAgICJJUHY2UHJpbWFyeSI6ICIiLCAgIklQdjZTZWNvbmRhcnkiOiAiIgogIH0sCiAgIkdvb2dsZSI6IHsKICAgICJDb250ZW50IjogIkdvb2dsZSBETlMiLAogICAgIkRlc2NyaXB0aW9uIjogIkdvb2dsZSBQdWJsaWMgRE5TLiBGYXN0IGFuZCByZWxpYWJsZS4gTm8gZmlsdGVyaW5nLiIsCiAgICAiQ2F0ZWdvcnkiOiAiRE5TIFByb3ZpZGVycyIsICJQYW5lbCI6ICJDb25maWciLCAiVHlwZSI6ICJCdXR0b24iLAogICAgIklQdjRQcmltYXJ5IjogIjguOC44LjgiLCAgICJJUHY0U2Vjb25kYXJ5IjogIjguOC40LjQiLAogICAgIklQdjZQcmltYXJ5IjogIjIwMDE6NDg2MDo0ODYwOjo4ODg4IiwgIklQdjZTZWNvbmRhcnkiOiAiMjAwMTo0ODYwOjQ4NjA6Ojg4NDQiLAogICAgIkxpbmsiOiAiaHR0cHM6Ly9kZXZlbG9wZXJzLmdvb2dsZS5jb20vc3BlZWQvcHVibGljLWRucyIKICB9LAogICJDbG91ZGZsYXJlIjogewogICAgIkNvbnRlbnQiOiAiQ2xvdWRmbGFyZSBETlMiLAogICAgIkRlc2NyaXB0aW9uIjogIkNsb3VkZmxhcmUncyBwcml2YWN5LWZpcnN0IEROUy4gRmFzdGVzdCBnbG9iYWxseS4gTm8gbG9nZ2luZy4iLAogICAgIkNhdGVnb3J5IjogIkROUyBQcm92aWRlcnMiLCAiUGFuZWwiOiAiQ29uZmlnIiwgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJJUHY0UHJpbWFyeSI6ICIxLjEuMS4xIiwgICAiSVB2NFNlY29uZGFyeSI6ICIxLjAuMC4xIiwKICAgICJJUHY2UHJpbWFyeSI6ICIyNjA2OjQ3MDA6NDcwMDo6MTExMSIsICJJUHY2U2Vjb25kYXJ5IjogIjI2MDY6NDcwMDo0NzAwOjoxMDAxIiwKICAgICJMaW5rIjogImh0dHBzOi8vMS4xLjEuMS9kbnMvIgogIH0sCiAgIkNsb3VkZmxhcmVNYWx3YXJlIjogewogICAgIkNvbnRlbnQiOiAiQ2xvdWRmbGFyZSAoQmxvY2sgTWFsd2FyZSkiLAogICAgIkRlc2NyaXB0aW9uIjogIkNsb3VkZmxhcmUgRE5TIHdpdGggbWFsd2FyZSBzaXRlIGJsb2NraW5nLiIsCiAgICAiQ2F0ZWdvcnkiOiAiRE5TIFByb3ZpZGVycyIsICJQYW5lbCI6ICJDb25maWciLCAiVHlwZSI6ICJCdXR0b24iLAogICAgIklQdjRQcmltYXJ5IjogIjEuMS4xLjIiLCAgICJJUHY0U2Vjb25kYXJ5IjogIjEuMC4wLjIiLAogICAgIklQdjZQcmltYXJ5IjogIjI2MDY6NDcwMDo0NzAwOjoxMTEyIiwgIklQdjZTZWNvbmRhcnkiOiAiMjYwNjo0NzAwOjQ3MDA6OjEwMDIiCiAgfSwKICAiUXVhZDkiOiB7CiAgICAiQ29udGVudCI6ICJRdWFkOSBETlMgKFNlY3VyaXR5KSIsCiAgICAiRGVzY3JpcHRpb24iOiAiQmxvY2tzIG1hbGljaW91cyBkb21haW5zLiBQcml2YWN5LWZvY3VzZWQsIG5vIHBlcnNvbmFsIGRhdGEgbG9nZ2luZy4iLAogICAgIkNhdGVnb3J5IjogIkROUyBQcm92aWRlcnMiLCAiUGFuZWwiOiAiQ29uZmlnIiwgIlR5cGUiOiAiQnV0dG9uIiwKICAgICJJUHY0UHJpbWFyeSI6ICI5LjkuOS45IiwgICAiSVB2NFNlY29uZGFyeSI6ICIxNDkuMTEyLjExMi4xMTIiLAogICAgIklQdjZQcmltYXJ5IjogIjI2MjA6ZmU6OmZlIiwgIklQdjZTZWNvbmRhcnkiOiAiMjYyMDpmZTo6OSIsCiAgICAiTGluayI6ICJodHRwczovL3d3dy5xdWFkOS5uZXQiCiAgfSwKICAiQWRHdWFyZCI6IHsKICAgICJDb250ZW50IjogIkFkR3VhcmQgRE5TIChBZCBCbG9jaykiLAogICAgIkRlc2NyaXB0aW9uIjogIkJsb2NrcyBhZHMgYW5kIHRyYWNrZXJzIGF0IHRoZSBETlMgbGV2ZWwuIEdvb2QgZm9yIGZhbWlseSB1c2UuIiwKICAgICJDYXRlZ29yeSI6ICJETlMgUHJvdmlkZXJzIiwgIlBhbmVsIjogIkNvbmZpZyIsICJUeXBlIjogIkJ1dHRvbiIsCiAgICAiSVB2NFByaW1hcnkiOiAiOTQuMTQwLjE0LjE0IiwgIklQdjRTZWNvbmRhcnkiOiAiOTQuMTQwLjE1LjE1IiwKICAgICJJUHY2UHJpbWFyeSI6ICIyYTEwOjUwYzA6OmFkMTpmZiIsICJJUHY2U2Vjb25kYXJ5IjogIjJhMTA6NTBjMDo6YWQyOmZmIiwKICAgICJMaW5rIjogImh0dHBzOi8vYWRndWFyZC1kbnMuaW8iCiAgfQp9Cg==')) | ConvertFrom-Json)
$sync.configs['presets'] = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ewogICJHYW1pbmdTZXR1cCI6IHsKICAgICJDb250ZW50IjogIkdhbWluZyBTZXR1cCIsCiAgICAiRGVzY3JpcHRpb24iOiAiT25lLWNsaWNrIGdhbWluZyByaWcgc2V0dXA6IENvbXBldGl0aXZlIFN0YWJsZSBtb2RlICsgUHJpdmFjeSB0d2Vha3MgKyBJbnN0YWxsIERpc2NvcmQgJiBTdGVhbSArIENsb3VkZmxhcmUgRE5TLiIsCiAgICAiQ2F0ZWdvcnkiOiAiUHJlc2V0cyIsCiAgICAiUGFuZWwiOiAgICAiQ29uZmlnIiwKICAgICJUeXBlIjogICAgICJCdXR0b24iLAogICAgIlR3ZWFrcyI6ICAgWyJXUEZUd2Vha3NUZWxlbWV0cnkiLCJXUEZUd2Vha3NEaXNhYmxlWGJveEdhbWVCYXIiLCJXUEZUd2Vha3NIaWdoUGVyZm9ybWFuY2VQb3dlciJdLAogICAgIkdhbWluZ01vZGUiOiAiV1RGTW9kZUNvbXBldGl0aXZlU3RhYmxlIiwKICAgICJBcHBzIjogICAgIFsiV1BGSW5zdGFsbERpc2NvcmQiLCJXUEZJbnN0YWxsU3RlYW0iXSwKICAgICJETlMiOiAgICAgICJDbG91ZGZsYXJlIgogIH0sCiAgIlByaXZhY3lIYXJkZW5lZCI6IHsKICAgICJDb250ZW50IjogIlByaXZhY3kgSGFyZGVuZWQiLAogICAgIkRlc2NyaXB0aW9uIjogIkRpc2FibGVzIGFsbCB0ZWxlbWV0cnksIENvcnRhbmEsIGFjdGl2aXR5IGhpc3RvcnksIGFkdmVydGlzaW5nIElELCBhbmQgbG9jYXRpb24gdHJhY2tpbmcuIiwKICAgICJDYXRlZ29yeSI6ICJQcmVzZXRzIiwKICAgICJQYW5lbCI6ICAgICJDb25maWciLAogICAgIlR5cGUiOiAgICAgIkJ1dHRvbiIsCiAgICAiVHdlYWtzIjogICBbIldQRlR3ZWFrc1RlbGVtZXRyeSIsIldQRlR3ZWFrc0Rpc2FibGVDb3J0YW5hIiwiV1BGVHdlYWtzRGlzYWJsZUFjdGl2aXR5SGlzdG9yeSIsIldQRlR3ZWFrc0Rpc2FibGVBZHZlcnRpc2luZ0lEIiwiV1BGVHdlYWtzRGlzYWJsZUxvY2F0aW9uVHJhY2tpbmciXSwKICAgICJETlMiOiAgICAgICJDbG91ZGZsYXJlIgogIH0sCiAgIkRldmVsb3BlclJlYWR5IjogewogICAgIkNvbnRlbnQiOiAiRGV2ZWxvcGVyIFJlYWR5IiwKICAgICJEZXNjcmlwdGlvbiI6ICJJbnN0YWxsIFZTIENvZGUsIEdpdCwgTm9kZS5qcywgUHl0aG9uLiBFbmFibGUgV1NMIGFuZCBTU0ggY2xpZW50LiIsCiAgICAiQ2F0ZWdvcnkiOiAiUHJlc2V0cyIsCiAgICAiUGFuZWwiOiAgICAiQ29uZmlnIiwKICAgICJUeXBlIjogICAgICJCdXR0b24iLAogICAgIkFwcHMiOiAgICAgWyJXUEZJbnN0YWxsVlNDb2RlIiwiV1BGSW5zdGFsbEdpdCIsIldQRkluc3RhbGxOb2RlSlMiLCJXUEZJbnN0YWxsUHl0aG9uIl0sCiAgICAiRmVhdHVyZXMiOiBbIldQRkZlYXR1cmVXU0wiLCJXUEZGZWF0dXJlU1NIQ2xpZW50Il0sCiAgICAiVHdlYWtzIjogICBbIldQRlR3ZWFrc1Nob3dGaWxlRXh0ZW5zaW9ucyIsIldQRlR3ZWFrc1Nob3dIaWRkZW5GaWxlcyJdCiAgfSwKICAiTWluaW1hbERlYmxvYXQiOiB7CiAgICAiQ29udGVudCI6ICJNaW5pbWFsIERlYmxvYXQiLAogICAgIkRlc2NyaXB0aW9uIjogIkxpZ2h0IHByaXZhY3kgYW5kIHBlcmZvcm1hbmNlIHR3ZWFrcyB3aXRob3V0IGFnZ3Jlc3NpdmUgY2hhbmdlcy4gU2FmZSBmb3IgYWxsIHVzZXJzLiIsCiAgICAiQ2F0ZWdvcnkiOiAiUHJlc2V0cyIsCiAgICAiUGFuZWwiOiAgICAiQ29uZmlnIiwKICAgICJUeXBlIjogICAgICJCdXR0b24iLAogICAgIlR3ZWFrcyI6ICAgWyJXUEZUd2Vha3NUZWxlbWV0cnkiLCJXUEZUd2Vha3NEaXNhYmxlQWR2ZXJ0aXNpbmdJRCIsIldQRlR3ZWFrc1Nob3dGaWxlRXh0ZW5zaW9ucyIsIldQRlR3ZWFrc0Rpc2FibGVGYXN0U3RhcnR1cCJdCiAgfSwKICAiQ29tcGV0aXRpdmVTdGFibGVQcmVzZXQiOiB7CiAgICAiQ29udGVudCI6ICJDb21wZXRpdGl2ZSBTdGFibGUgRnVsbCBTZXR1cCIsCiAgICAiRGVzY3JpcHRpb24iOiAiRnVsbCBjb21wZXRpdGl2ZSBnYW1pbmcgcHJvZmlsZTogQ29tcGV0aXRpdmUgU3RhYmxlIG1vZGUgKyBkaXNhYmxlIFhib3ggR2FtZSBCYXIgKyBDbG91ZGZsYXJlIEROUy4iLAogICAgIkNhdGVnb3J5IjogIlByZXNldHMiLAogICAgIlBhbmVsIjogICAgIkNvbmZpZyIsCiAgICAiVHlwZSI6ICAgICAiQnV0dG9uIiwKICAgICJHYW1pbmdNb2RlIjogIldURk1vZGVDb21wZXRpdGl2ZVN0YWJsZSIsCiAgICAiVHdlYWtzIjogICBbIldQRlR3ZWFrc0Rpc2FibGVYYm94R2FtZUJhciIsIldQRlR3ZWFrc1RlbGVtZXRyeSJdLAogICAgIkROUyI6ICAgICAgIkNsb3VkZmxhcmUiCiAgfQp9Cg==')) | ConvertFrom-Json)

# --- EMBEDDED XAML (Base64-encoded UTF-8) ---
$inputXML = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PFdpbmRvdwogICAgeG1sbnM9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd2luZngvMjAwNi94YW1sL3ByZXNlbnRhdGlvbiIKICAgIHhtbG5zOng9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd2luZngvMjAwNi94YW1sIgogICAgVGl0bGU9IldpblR3ZWFrIFV0aWxpdHkgdjMuMCIKICAgIFdpZHRoPSIxMTAwIiBIZWlnaHQ9Ijc1MCIKICAgIE1pbldpZHRoPSI5MDAiIE1pbkhlaWdodD0iNjAwIgogICAgV2luZG93U3RhcnR1cExvY2F0aW9uPSJDZW50ZXJTY3JlZW4iCiAgICBCYWNrZ3JvdW5kPSIjMEQwRDEyIgogICAgRm9yZWdyb3VuZD0iI0U4RThGMCIKICAgIEZvbnRGYW1pbHk9IlNlZ29lIFVJIj4KCiAgICA8V2luZG93LlJlc291cmNlcz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJCZ1ByaW1hcnkiICAgIENvbG9yPSIjMEQwRDEyIi8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQmdTZWNvbmRhcnkiICBDb2xvcj0iIzEzMTMxQSIvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJnQ2FyZCIgICAgICAgQ29sb3I9IiMxQTFBMjQiLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJCZ0hvdmVyIiAgICAgIENvbG9yPSIjMjIyMjNBIi8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQWNjZW50Qmx1ZSIgICBDb2xvcj0iIzRGQzNGNyIvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkFjY2VudEdyZWVuIiAgQ29sb3I9IiM2OUYwQUUiLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJBY2NlbnRPcmFuZ2UiIENvbG9yPSIjRkZCNzREIi8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQWNjZW50UmVkIiAgICBDb2xvcj0iI0VGNTM1MCIvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlRleHRQcmltYXJ5IiAgQ29sb3I9IiNFOEU4RjAiLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJUZXh0TXV0ZWQiICAgIENvbG9yPSIjODg4ODk5Ii8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQm9yZGVyIiAgICAgICBDb2xvcj0iIzJBMkEzRSIvPgoKICAgICAgICA8U3R5bGUgeDpLZXk9IldUVVRhYkl0ZW0iIFRhcmdldFR5cGU9IlRhYkl0ZW0iPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiAgICAgIFZhbHVlPSJUcmFuc3BhcmVudCIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb3JlZ3JvdW5kIiAgICAgIFZhbHVlPSIjODg4ODk5Ii8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvbnRTaXplIiAgICAgICAgVmFsdWU9IjEzIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvbnRXZWlnaHQiICAgICAgVmFsdWU9IlNlbWlCb2xkIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlBhZGRpbmciICAgICAgICAgVmFsdWU9IjE4LDEwIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlclRoaWNrbmVzcyIgVmFsdWU9IjAiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iVGVtcGxhdGUiPgogICAgICAgICAgICAgICAgPFNldHRlci5WYWx1ZT4KICAgICAgICAgICAgICAgICAgICA8Q29udHJvbFRlbXBsYXRlIFRhcmdldFR5cGU9IlRhYkl0ZW0iPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIHg6TmFtZT0iVGFiQm9yZGVyIiBCYWNrZ3JvdW5kPSJUcmFuc3BhcmVudCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCb3JkZXJUaGlja25lc3M9IjAsMCwwLDIiIEJvcmRlckJydXNoPSJUcmFuc3BhcmVudCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBQYWRkaW5nPSIxOCwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29udGVudFByZXNlbnRlci8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29udHJvbFRlbXBsYXRlLlRyaWdnZXJzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRyaWdnZXIgUHJvcGVydHk9IklzU2VsZWN0ZWQiIFZhbHVlPSJUcnVlIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFRhcmdldE5hbWU9IlRhYkJvcmRlciIgUHJvcGVydHk9IkJvcmRlckJydXNoIiBWYWx1ZT0iIzRGQzNGNyIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgVGFyZ2V0TmFtZT0iVGFiQm9yZGVyIiBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgIFZhbHVlPSIjMUExQTI0Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgVmFsdWU9IiM0RkMzRjciLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvVHJpZ2dlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUcmlnZ2VyIFByb3BlcnR5PSJJc01vdXNlT3ZlciIgVmFsdWU9IlRydWUiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgVGFyZ2V0TmFtZT0iVGFiQm9yZGVyIiBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgVmFsdWU9IiMyMjIyM0EiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvVHJpZ2dlcj4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Db250cm9sVGVtcGxhdGUuVHJpZ2dlcnM+CiAgICAgICAgICAgICAgICAgICAgPC9Db250cm9sVGVtcGxhdGU+CiAgICAgICAgICAgICAgICA8L1NldHRlci5WYWx1ZT4KICAgICAgICAgICAgPC9TZXR0ZXI+CiAgICAgICAgPC9TdHlsZT4KCiAgICAgICAgPFN0eWxlIHg6S2V5PSJXVFVCdXR0b24iIFRhcmdldFR5cGU9IkJ1dHRvbiI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiICAgICAgVmFsdWU9IiMxRTJBM0EiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgICAgICBWYWx1ZT0iIzRGQzNGNyIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJCcnVzaCIgICAgIFZhbHVlPSIjMkEzRjU1Ii8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlclRoaWNrbmVzcyIgVmFsdWU9IjEiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iUGFkZGluZyIgICAgICAgICBWYWx1ZT0iMTQsNyIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250U2l6ZSIgICAgICAgIFZhbHVlPSIxMiIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250V2VpZ2h0IiAgICAgIFZhbHVlPSJTZW1pQm9sZCIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDdXJzb3IiICAgICAgICAgIFZhbHVlPSJIYW5kIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlRlbXBsYXRlIj4KICAgICAgICAgICAgICAgIDxTZXR0ZXIuVmFsdWU+CiAgICAgICAgICAgICAgICAgICAgPENvbnRyb2xUZW1wbGF0ZSBUYXJnZXRUeXBlPSJCdXR0b24iPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IntUZW1wbGF0ZUJpbmRpbmcgQmFja2dyb3VuZH0iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQm9yZGVyQnJ1c2g9IntUZW1wbGF0ZUJpbmRpbmcgQm9yZGVyQnJ1c2h9IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJvcmRlclRoaWNrbmVzcz0ie1RlbXBsYXRlQmluZGluZyBCb3JkZXJUaGlja25lc3N9IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIENvcm5lclJhZGl1cz0iNiIgUGFkZGluZz0ie1RlbXBsYXRlQmluZGluZyBQYWRkaW5nfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29udGVudFByZXNlbnRlciBIb3Jpem9udGFsQWxpZ25tZW50PSJDZW50ZXIiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxDb250cm9sVGVtcGxhdGUuVHJpZ2dlcnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VHJpZ2dlciBQcm9wZXJ0eT0iSXNNb3VzZU92ZXIiIFZhbHVlPSJUcnVlIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiAgVmFsdWU9IiMyNjM5NEQiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJCcnVzaCIgVmFsdWU9IiM0RkMzRjciLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvVHJpZ2dlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUcmlnZ2VyIFByb3BlcnR5PSJJc1ByZXNzZWQiIFZhbHVlPSJUcnVlIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiBWYWx1ZT0iIzBFMUYyRSIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9UcmlnZ2VyPgogICAgICAgICAgICAgICAgICAgICAgICA8L0NvbnRyb2xUZW1wbGF0ZS5UcmlnZ2Vycz4KICAgICAgICAgICAgICAgICAgICA8L0NvbnRyb2xUZW1wbGF0ZT4KICAgICAgICAgICAgICAgIDwvU2V0dGVyLlZhbHVlPgogICAgICAgICAgICA8L1NldHRlcj4KICAgICAgICA8L1N0eWxlPgoKICAgICAgICA8U3R5bGUgeDpLZXk9IldUVUJ1dHRvbkdyZWVuIiBUYXJnZXRUeXBlPSJCdXR0b24iIEJhc2VkT249IntTdGF0aWNSZXNvdXJjZSBXVFVCdXR0b259Ij4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgIFZhbHVlPSIjMUEyRTIyIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvcmVncm91bmQiICBWYWx1ZT0iIzY5RjBBRSIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJCcnVzaCIgVmFsdWU9IiMyQTRFMzUiLz4KICAgICAgICA8L1N0eWxlPgoKICAgICAgICA8U3R5bGUgeDpLZXk9IldUVUJ1dHRvblJlZCIgVGFyZ2V0VHlwZT0iQnV0dG9uIiBCYXNlZE9uPSJ7U3RhdGljUmVzb3VyY2UgV1RVQnV0dG9ufSI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiICBWYWx1ZT0iIzJFMUExQSIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb3JlZ3JvdW5kIiAgVmFsdWU9IiNFRjUzNTAiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyQnJ1c2giIFZhbHVlPSIjNEUyQTJBIi8+CiAgICAgICAgPC9TdHlsZT4KCiAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9IkNoZWNrQm94Ij4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgICAgICAgICAgICAgIFZhbHVlPSIjQzhDOEQ4Ii8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvbnRTaXplIiAgICAgICAgICAgICAgICBWYWx1ZT0iMTIiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iTWFyZ2luIiAgICAgICAgICAgICAgICAgIFZhbHVlPSIwLDMiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iVmVydGljYWxDb250ZW50QWxpZ25tZW50IiBWYWx1ZT0iQ2VudGVyIi8+CiAgICAgICAgPC9TdHlsZT4KCiAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9Ikdyb3VwQm94Ij4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgICAgICBWYWx1ZT0iIzRGQzNGNyIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250U2l6ZSIgICAgICAgIFZhbHVlPSIxMiIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250V2VpZ2h0IiAgICAgIFZhbHVlPSJCb2xkIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlckJydXNoIiAgICAgVmFsdWU9IiMyQTJBM0UiLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyVGhpY2tuZXNzIiBWYWx1ZT0iMSIvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJNYXJnaW4iICAgICAgICAgIFZhbHVlPSIwLDYsMCwwIi8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlBhZGRpbmciICAgICAgICAgVmFsdWU9IjgiLz4KICAgICAgICA8L1N0eWxlPgogICAgPC9XaW5kb3cuUmVzb3VyY2VzPgoKICAgIDxHcmlkPgogICAgICAgIDxHcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iLz4KICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSIqIi8+CiAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIvPgogICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgPCEtLSBUSVRMRSBCQVIgLS0+CiAgICAgICAgPEJvcmRlciBHcmlkLlJvdz0iMCIgQmFja2dyb3VuZD0iIzBBMEExMCIgQm9yZGVyQnJ1c2g9IiMyQTJBM0UiCiAgICAgICAgICAgICAgICBCb3JkZXJUaGlja25lc3M9IjAsMCwwLDEiIFBhZGRpbmc9IjIwLDEyIj4KICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIvPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIi8+CiAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCIgT3JpZW50YXRpb249Ikhvcml6b250YWwiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iW1dUVV0iIEZvbnRTaXplPSIxNiIgRm9udFdlaWdodD0iQm9sZCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM0RkMzRjciIE1hcmdpbj0iMCwwLDEwLDAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiLz4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJXaW5Ud2VhayBVdGlsaXR5IiBGb250U2l6ZT0iMTgiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNFOEU4RjAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJ2My4wIC0gTW9kdWxhciBXaW5kb3dzIFN5c3RlbSBPcHRpbWl6ZXIiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjNEZDM0Y3IiBNYXJnaW49IjAsMSwwLDAiLz4KICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSIgT3JpZW50YXRpb249Ikhvcml6b250YWwiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMkUyMiIgQ29ybmVyUmFkaXVzPSI0IiBQYWRkaW5nPSI4LDQiIE1hcmdpbj0iMCwwLDgsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJBZG1pblN0YXR1c1RleHQiIFRleHQ9IiogQWRtaW4iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjNjlGMEFFIi8+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUUxRTJFIiBDb3JuZXJSYWRpdXM9IjQiIFBhZGRpbmc9IjgsNCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJDaGVja3BvaW50Q291bnRUZXh0IiBUZXh0PSIwIENoZWNrcG9pbnRzIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iIzg4ODg5OSIvPgogICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgIDwhLS0gTUFJTiBUQUIgQ09OVFJPTCAtLT4KICAgICAgICA8VGFiQ29udHJvbCBHcmlkLlJvdz0iMSIgeDpOYW1lPSJNYWluVGFiQ29udHJvbCIKICAgICAgICAgICAgICAgICAgICBCYWNrZ3JvdW5kPSIjMEQwRDEyIiBCb3JkZXJUaGlja25lc3M9IjAiIFBhZGRpbmc9IjAiPgogICAgICAgICAgICA8VGFiQ29udHJvbC5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iVGFiUGFuZWwiPgogICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiIFZhbHVlPSIjMEEwQTEwIi8+CiAgICAgICAgICAgICAgICA8L1N0eWxlPgogICAgICAgICAgICA8L1RhYkNvbnRyb2wuUmVzb3VyY2VzPgoKICAgICAgICAgICAgPCEtLSBJTlNUQUxMIFRBQiAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gSGVhZGVyPSJbK10gSW5zdGFsbCIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBXVFVUYWJJdGVtfSI+CiAgICAgICAgICAgICAgICA8R3JpZCBNYXJnaW49IjE2Ij4KICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IjI4MCIvPgogICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICA8U2Nyb2xsVmlld2VyIEdyaWQuQ29sdW1uPSIwIiBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMCwwLDEyLDAiPgogICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCB4Ok5hbWU9Ikluc3RhbGxQYW5lbCIvPgogICAgICAgICAgICAgICAgICAgIDwvU2Nyb2xsVmlld2VyPgogICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgR3JpZC5Db2x1bW49IjEiIEJhY2tncm91bmQ9IiMxMzEzMUEiIENvcm5lclJhZGl1cz0iOCIgUGFkZGluZz0iMTQiPgogICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iQXBwIEFjdGlvbnMiIEZvbnRXZWlnaHQ9IkJvbGQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM0RkMzRjciIEZvbnRTaXplPSIxMyIgTWFyZ2luPSIwLDAsMCwxMiIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9Ikluc3RhbGxTZWxlY3RlZEJ0biIgICBDb250ZW50PSJJbnN0YWxsIFNlbGVjdGVkIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbkdyZWVufSIgTWFyZ2luPSIwLDAsMCw4IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBIb3Jpem9udGFsQWxpZ25tZW50PSJTdHJldGNoIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iVW5pbnN0YWxsU2VsZWN0ZWRCdG4iIENvbnRlbnQ9IlVuaW5zdGFsbCBTZWxlY3RlZCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBXVFVCdXR0b25SZWR9IiAgIE1hcmdpbj0iMCwwLDAsOCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgSG9yaXpvbnRhbEFsaWdubWVudD0iU3RyZXRjaCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNlcGFyYXRvciBCYWNrZ3JvdW5kPSIjMkEyQTNFIiBNYXJnaW49IjAsOCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTZWxlY3RlZCBBcHBzOiIgRm9yZWdyb3VuZD0iIzg4ODg5OSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBNYXJnaW49IjAsMCwwLDYiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxMaXN0Qm94IHg6TmFtZT0iU2VsZWN0ZWRBcHBzTGlzdCIgQmFja2dyb3VuZD0iIzBEMEQxMiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJvcmRlckJydXNoPSIjMkEyQTNFIiBGb3JlZ3JvdW5kPSIjQzhDOEQ4IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBIZWlnaHQ9IjIwMCIgTWFyZ2luPSIwLDAsMCw4Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlByb2dyZXNzOiIgRm9yZWdyb3VuZD0iIzg4ODg5OSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBNYXJnaW49IjAsNiwwLDQiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxQcm9ncmVzc0JhciB4Ok5hbWU9Ikluc3RhbGxQcm9ncmVzcyIgSGVpZ2h0PSI2IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMyMjIyM0EiIEZvcmVncm91bmQ9IiM0RkMzRjciCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQm9yZGVyVGhpY2tuZXNzPSIwIiBNaW5pbXVtPSIwIiBNYXhpbXVtPSIxMDAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJJbnN0YWxsU3RhdHVzIiBUZXh0PSJSZWFkeSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjODg4ODk5IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBNYXJnaW49IjAsNiwwLDAiIFRleHRXcmFwcGluZz0iV3JhcCIvPgogICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gVFdFQUtTIFRBQiAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gSGVhZGVyPSJbfl0gVHdlYWtzIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVVRhYkl0ZW19Ij4KICAgICAgICAgICAgICAgIDxHcmlkIE1hcmdpbj0iMTYiPgogICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIvPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iMjgwIi8+CiAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgR3JpZC5Db2x1bW49IjAiIFZlcnRpY2FsU2Nyb2xsQmFyVmlzaWJpbGl0eT0iQXV0byIgTWFyZ2luPSIwLDAsMTIsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIHg6TmFtZT0iVHdlYWtzUGFuZWwiLz4KICAgICAgICAgICAgICAgICAgICA8L1Njcm9sbFZpZXdlcj4KICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEdyaWQuQ29sdW1uPSIxIiBCYWNrZ3JvdW5kPSIjMTMxMzFBIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjE0Ij4KICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlR3ZWFrIEFjdGlvbnMiIEZvbnRXZWlnaHQ9IkJvbGQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM0RkMzRjciIEZvbnRTaXplPSIxMyIgTWFyZ2luPSIwLDAsMCwxMiIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9IkFwcGx5VHdlYWtzQnRuIiBDb250ZW50PSJBcHBseSBTZWxlY3RlZCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBXVFVCdXR0b25HcmVlbn0iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhvcml6b250YWxBbGlnbm1lbnQ9IlN0cmV0Y2giIE1hcmdpbj0iMCwwLDAsOCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9IlVuZG9Ud2Vha3NCdG4iICBDb250ZW50PSJVbmRvIFNlbGVjdGVkIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbn0iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhvcml6b250YWxBbGlnbm1lbnQ9IlN0cmV0Y2giIE1hcmdpbj0iMCwwLDAsOCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNlcGFyYXRvciBCYWNrZ3JvdW5kPSIjMkEyQTNFIiBNYXJnaW49IjAsOCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJUd2VhayBJbmZvOiIgRm9yZWdyb3VuZD0iIzg4ODg5OSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBNYXJnaW49IjAsMCwwLDYiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJUd2Vha0Rlc2NyaXB0aW9uIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUZXh0PSJTZWxlY3QgYSB0d2VhayB0byBzZWUgZGV0YWlscy4iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiNDOEM4RDgiIEZvbnRTaXplPSIxMSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVGV4dFdyYXBwaW5nPSJXcmFwIiBNYXJnaW49IjAsMCwwLDgiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgeDpOYW1lPSJUd2Vha1dhcm5pbmdCb3giIEJhY2tncm91bmQ9IiMyRTFBMUEiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIENvcm5lclJhZGl1cz0iNCIgUGFkZGluZz0iOCw2IiBWaXNpYmlsaXR5PSJDb2xsYXBzZWQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJUd2Vha1dhcm5pbmdUZXh0IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iI0VGNTM1MCIgRm9udFNpemU9IjExIiBUZXh0V3JhcHBpbmc9IldyYXAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciB4Ok5hbWU9IlJlc3RhcnRCYWRnZSIgQmFja2dyb3VuZD0iIzJFMjIwMCIgQ29ybmVyUmFkaXVzPSI0IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBQYWRkaW5nPSI4LDYiIE1hcmdpbj0iMCw2LDAsMCIgVmlzaWJpbGl0eT0iQ29sbGFwc2VkIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlJlc3RhcnQgUmVxdWlyZWQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb3JlZ3JvdW5kPSIjRkZCNzREIiBGb250U2l6ZT0iMTEiIEZvbnRXZWlnaHQ9IkJvbGQiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gR0FNSU5HIFRBQiAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gSGVhZGVyPSJbR10gR2FtaW5nIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVVRhYkl0ZW19Ij4KICAgICAgICAgICAgICAgIDxHcmlkIE1hcmdpbj0iMTYiPgogICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgTWluV2lkdGg9IjQwMCIvPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iMzQwIi8+CiAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCIgTWFyZ2luPSIwLDAsMTYsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxHcm91cEJveCBIZWFkZXI9IlBlcmZvcm1hbmNlIE1vZGVzIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIHg6TmFtZT0iR2FtaW5nTW9kZXNQYW5lbCIgTWFyZ2luPSIwLDQiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Hcm91cEJveD4KICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iU2FmZXR5IiBNYXJnaW49IjAsMTIsMCwwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxXcmFwUGFuZWwgTWFyZ2luPSIwLDQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24geDpOYW1lPSJDcmVhdGVDaGVja3BvaW50QnRuIiAgQ29udGVudD0iQ3JlYXRlIENoZWNrcG9pbnQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbkdyZWVufSIgTWFyZ2luPSIwLDAsOCw4Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9IlJlc3RvcmVDaGVja3BvaW50QnRuIiBDb250ZW50PSJSZXN0b3JlIENoZWNrcG9pbnQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbn0iICAgICAgTWFyZ2luPSIwLDAsOCw4Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9Ikxpc3RDaGVja3BvaW50c0J0biIgICBDb250ZW50PSJMaXN0IENoZWNrcG9pbnRzIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBXVFVCdXR0b259IiAgICAgIE1hcmdpbj0iMCwwLDgsOCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24geDpOYW1lPSJEZWxldGVDaGVja3BvaW50QnRuIiAgQ29udGVudD0iRGVsZXRlIENoZWNrcG9pbnQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvblJlZH0iICAgTWFyZ2luPSIwLDAsOCw4Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1dyYXBQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Hcm91cEJveD4KICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iU3RhdHVzIiBNYXJnaW49IjAsMTIsMCwwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIE1hcmdpbj0iMCw0Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIHg6TmFtZT0iR2FtaW5nU3RhdHVzVGV4dCIgVGV4dD0iUmVhZHkgLSBObyBtb2RlIGFwcGxpZWQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb3JlZ3JvdW5kPSIjNjlGMEFFIiBGb250U2l6ZT0iMTIiIEZvbnRXZWlnaHQ9IlNlbWlCb2xkIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayB4Ok5hbWU9IkdhbWluZ0VzdGltYXRlZEltcGFjdCIgVGV4dD0iIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjODg4ODk5IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTWFyZ2luPSIwLDQsMCwwIiBUZXh0V3JhcHBpbmc9IldyYXAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Hcm91cEJveD4KICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CgogICAgICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgR3JpZC5Db2x1bW49IjEiIFZlcnRpY2FsU2Nyb2xsQmFyVmlzaWJpbGl0eT0iQXV0byI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iSW5kaXZpZHVhbCBUd2Vha3MiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIHg6TmFtZT0iR2FtaW5nVHdlYWtzUGFuZWwiIE1hcmdpbj0iMCw0Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyb3VwQm94PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iR1BVIENvbnRyb2wiIE1hcmdpbj0iMCwxMiwwLDAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIE1hcmdpbj0iMCw0Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQgTWFyZ2luPSIwLDAsMCw2Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSI4MCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlZlbmRvcjoiIEZvcmVncm91bmQ9IiM4ODg4OTkiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRTaXplPSIxMSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbWJvQm94IHg6TmFtZT0iR1BVVmVuZG9yQ29tYm8iIEdyaWQuQ29sdW1uPSIxIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMxQTFBMjQiIEZvcmVncm91bmQ9IiNDOEM4RDgiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQm9yZGVyQnJ1c2g9IiMyQTJBM0UiIEZvbnRTaXplPSIxMSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbWJvQm94SXRlbSBDb250ZW50PSJOVklESUEiIElzU2VsZWN0ZWQ9IlRydWUiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29tYm9Cb3hJdGVtIENvbnRlbnQ9IkFNRCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb21ib0JveEl0ZW0gQ29udGVudD0iSW50ZWwiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQ29tYm9Cb3g+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQgTWFyZ2luPSIwLDAsMCw2Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSI4MCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IjQwIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkxvY2sgTUh6OiIgRm9yZWdyb3VuZD0iIzg4ODg5OSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2xpZGVyIHg6TmFtZT0iR1BVQ2xvY2tTbGlkZXIiIEdyaWQuQ29sdW1uPSIxIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBNaW5pbXVtPSI1MDAiIE1heGltdW09IjMwMDAiIFZhbHVlPSIxODAwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUaWNrRnJlcXVlbmN5PSIxMDAiIElzU25hcFRvVGlja0VuYWJsZWQ9IlRydWUiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM0RkMzRjciLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJHUFVDbG9ja1ZhbHVlIiBHcmlkLkNvbHVtbj0iMiIgVGV4dD0iMTgwMCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iI0M4QzhEOCIgRm9udFNpemU9IjExIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiBUZXh0QWxpZ25tZW50PSJSaWdodCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkIE1hcmdpbj0iMCwwLDAsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IjgwIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iNDAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUG93ZXIgJToiIEZvcmVncm91bmQ9IiM4ODg4OTkiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRTaXplPSIxMSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNsaWRlciB4Ok5hbWU9IkdQVVBvd2VyU2xpZGVyIiBHcmlkLkNvbHVtbj0iMSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTWluaW11bT0iMzAiIE1heGltdW09IjEyMCIgVmFsdWU9IjgwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUaWNrRnJlcXVlbmN5PSI1IiBJc1NuYXBUb1RpY2tFbmFibGVkPSJUcnVlIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb3JlZ3JvdW5kPSIjNEZDM0Y3Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIHg6TmFtZT0iR1BVUG93ZXJWYWx1ZSIgR3JpZC5Db2x1bW49IjIiIFRleHQ9IjgwJSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iI0M4QzhEOCIgRm9udFNpemU9IjExIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiBUZXh0QWxpZ25tZW50PSJSaWdodCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24geDpOYW1lPSJBcHBseUdQVUJ0biIgQ29udGVudD0iQXBwbHkgR1BVIFNldHRpbmdzIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgV1RVQnV0dG9uR3JlZW59IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhvcml6b250YWxBbGlnbm1lbnQ9IlN0cmV0Y2giLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyb3VwQm94PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iVG9vbHMiIE1hcmdpbj0iMCwxMiwwLDAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxXcmFwUGFuZWwgTWFyZ2luPSIwLDQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iTGF1bmNoTW9uaXRvckJ0biIgQ29udGVudD0iTW9uaXRvciIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDgsMCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iUnVuQmVuY2htYXJrQnRuIiAgQ29udGVudD0iQmVuY2htYXJrIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgV1RVQnV0dG9ufSIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvV3JhcFBhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Hcm91cEJveD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgIDwvU2Nyb2xsVmlld2VyPgogICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgICAgICA8IS0tIEZFQVRVUkVTIFRBQiAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gSGVhZGVyPSJbRl0gRmVhdHVyZXMiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgV1RVVGFiSXRlbX0iPgogICAgICAgICAgICAgICAgPEdyaWQgTWFyZ2luPSIxNiI+CiAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIi8+CiAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIyODAiLz4KICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgPFNjcm9sbFZpZXdlciBHcmlkLkNvbHVtbj0iMCIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBNYXJnaW49IjAsMCwxMiwwIj4KICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgeDpOYW1lPSJGZWF0dXJlc1BhbmVsIi8+CiAgICAgICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBHcmlkLkNvbHVtbj0iMSIgQmFja2dyb3VuZD0iIzEzMTMxQSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJGZWF0dXJlIEFjdGlvbnMiIEZvbnRXZWlnaHQ9IkJvbGQiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM0RkMzRjciIEZvbnRTaXplPSIxMyIgTWFyZ2luPSIwLDAsMCwxMiIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiB4Ok5hbWU9IkVuYWJsZUZlYXR1cmVzQnRuIiAgQ29udGVudD0iRW5hYmxlIFNlbGVjdGVkIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbkdyZWVufSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgSG9yaXpvbnRhbEFsaWdubWVudD0iU3RyZXRjaCIgTWFyZ2luPSIwLDAsMCw4Ii8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iRGlzYWJsZUZlYXR1cmVzQnRuIiBDb250ZW50PSJEaXNhYmxlIFNlbGVjdGVkIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvblJlZH0iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhvcml6b250YWxBbGlnbm1lbnQ9IlN0cmV0Y2giLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXBhcmF0b3IgQmFja2dyb3VuZD0iIzJBMkEzRSIgTWFyZ2luPSIwLDEyIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIHg6TmFtZT0iRmVhdHVyZURlc2NyaXB0aW9uIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUZXh0PSJTZWxlY3QgYSBmZWF0dXJlIHRvIHNlZSBkZXRhaWxzLiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iI0M4QzhEOCIgRm9udFNpemU9IjExIiBUZXh0V3JhcHBpbmc9IldyYXAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgICAgICA8IS0tIFJFUEFJUiBUQUIgLS0+CiAgICAgICAgICAgIDxUYWJJdGVtIEhlYWRlcj0iW1JdIFJlcGFpciIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBXVFVUYWJJdGVtfSI+CiAgICAgICAgICAgICAgICA8R3JpZCBNYXJnaW49IjE2Ij4KICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiLz4KICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IjI4MCIvPgogICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICA8U2Nyb2xsVmlld2VyIEdyaWQuQ29sdW1uPSIwIiBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMCwwLDEyLDAiPgogICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCB4Ok5hbWU9IlJlcGFpclBhbmVsIi8+CiAgICAgICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBHcmlkLkNvbHVtbj0iMSIgQmFja2dyb3VuZD0iIzEzMTMxQSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJSZXBhaXIgSW5mbyIgRm9udFdlaWdodD0iQm9sZCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iIzRGQzNGNyIgRm9udFNpemU9IjEzIiBNYXJnaW49IjAsMCwwLDEyIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIHg6TmFtZT0iUmVwYWlyRGVzY3JpcHRpb24iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHQ9IlNlbGVjdCBhIHJlcGFpciBhY3Rpb24gdG8gc2VlIGRldGFpbHMuIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb3JlZ3JvdW5kPSIjQzhDOEQ4IiBGb250U2l6ZT0iMTEiIFRleHRXcmFwcGluZz0iV3JhcCIvPgogICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gQ09ORklHIFRBQiAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gSGVhZGVyPSJbQ10gQ29uZmlnIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVVRhYkl0ZW19Ij4KICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgTWFyZ2luPSIxNiIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPEdyb3VwQm94IEhlYWRlcj0iRE5TIENvbmZpZ3VyYXRpb24iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgTWFyZ2luPSIwLDgiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iU2VsZWN0IGEgcHJvdmlkZXIgdG8gYXBwbHkgdG8gYWxsIGFjdGl2ZSBhZGFwdGVycyAoSVB2NCArIElQdjYpOiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM4ODg4OTkiIEZvbnRTaXplPSIxMSIgTWFyZ2luPSIwLDAsMCwxMCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxXcmFwUGFuZWwgeDpOYW1lPSJETlNQYW5lbCIgTWFyZ2luPSIwLDAsMCwxMCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJETlNDdXJyZW50VGV4dCIgVGV4dD0iQ3VycmVudDogTG9hZGluZy4uLiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iIzRGQzNGNyIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8L0dyb3VwQm94PgogICAgICAgICAgICAgICAgICAgICAgICA8R3JvdXBCb3ggSGVhZGVyPSJPbmUtQ2xpY2sgUHJlc2V0cyIgTWFyZ2luPSIwLDEyLDAsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBNYXJnaW49IjAsOCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJBcHBseSBhIGN1cmF0ZWQgY29tYmluYXRpb24gb2YgdHdlYWtzLCBtb2RlLCBhcHBzLCBhbmQgRE5TIGluIG9uZSBjbGljazoiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb3JlZ3JvdW5kPSIjODg4ODk5IiBGb250U2l6ZT0iMTEiIE1hcmdpbj0iMCwwLDAsMTAiLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8SXRlbXNDb250cm9sIHg6TmFtZT0iUHJlc2V0c1BhbmVsIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JvdXBCb3g+CiAgICAgICAgICAgICAgICAgICAgICAgIDxHcm91cEJveCBIZWFkZXI9IlJvbGxiYWNrIGFuZCBDaGVja3BvaW50cyIgTWFyZ2luPSIwLDEyLDAsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBNYXJnaW49IjAsOCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPExpc3RCb3ggeDpOYW1lPSJDaGVja3BvaW50c0xpc3QiIEJhY2tncm91bmQ9IiMwRDBEMTIiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQm9yZGVyQnJ1c2g9IiMyQTJBM0UiIEZvcmVncm91bmQ9IiNDOEM4RDgiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjExIiBIZWlnaHQ9IjE0MCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxXcmFwUGFuZWwgTWFyZ2luPSIwLDgiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iUmVzdG9yZUZyb21MaXN0QnRuIiBDb250ZW50PSJSZXN0b3JlIFNlbGVjdGVkIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgV1RVQnV0dG9ufSIgICAgTWFyZ2luPSIwLDAsOCwwIi8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24geDpOYW1lPSJEZWxldGVGcm9tTGlzdEJ0biIgIENvbnRlbnQ9IkRlbGV0ZSBTZWxlY3RlZCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvblJlZH0iIE1hcmdpbj0iMCwwLDgsMCIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIHg6TmFtZT0iQ29tcGFyZUNoa0J0biIgICAgICBDb250ZW50PSJDb21wYXJlIFR3byIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFdUVUJ1dHRvbn0iLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1dyYXBQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Hcm91cEJveD4KICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICA8L1Njcm9sbFZpZXdlcj4KICAgICAgICAgICAgPC9UYWJJdGVtPgogICAgICAgIDwvVGFiQ29udHJvbD4KCiAgICAgICAgPCEtLSBTVEFUVVMgQkFSIC0tPgogICAgICAgIDxCb3JkZXIgR3JpZC5Sb3c9IjIiIEJhY2tncm91bmQ9IiMwQTBBMTAiIEJvcmRlckJydXNoPSIjMkEyQTNFIgogICAgICAgICAgICAgICAgQm9yZGVyVGhpY2tuZXNzPSIwLDEsMCwwIiBQYWRkaW5nPSIxNiw4Ij4KICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIvPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIyMDAiLz4KICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIwIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciI+CiAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayB4Ok5hbWU9IlN0YXR1c1RleHQiIFRleHQ9IlJlYWR5IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9yZWdyb3VuZD0iIzY5RjBBRSIgRm9udFNpemU9IjEyIiBGb250V2VpZ2h0PSJTZW1pQm9sZCIvPgogICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgeDpOYW1lPSJTdGF0dXNEZXRhaWwiIFRleHQ9IiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvcmVncm91bmQ9IiM4ODg4OTkiIEZvbnRTaXplPSIxMSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIE1hcmdpbj0iMTIsMCwwLDAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiLz4KICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgIDxQcm9ncmVzc0JhciBHcmlkLkNvbHVtbj0iMSIgeDpOYW1lPSJHbG9iYWxQcm9ncmVzcyIgSGVpZ2h0PSI0IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMyMjIyM0EiIEZvcmVncm91bmQ9IiM0RkMzRjciCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQm9yZGVyVGhpY2tuZXNzPSIwIiBNaW5pbXVtPSIwIiBNYXhpbXVtPSIxMDAiIFZhbHVlPSIwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiLz4KICAgICAgICAgICAgPC9HcmlkPgogICAgICAgIDwvQm9yZGVyPgogICAgPC9HcmlkPgo8L1dpbmRvdz4K'))


