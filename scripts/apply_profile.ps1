# apply_profile.ps1 - JSON profile processor
param(
    [Parameter(Mandatory=$true)]
    [string]$Profile,
    [string]$Log = "",
    [switch]$DryRun
)

$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$BaseDir   = Split-Path $ScriptDir -Parent
$ModulesDir = Join-Path $BaseDir "modules"

if (-not $Log) {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $Log = Join-Path $BaseDir "logs\profile_$ts.log"
}

function Write-Log {
    param([string]$msg, [string]$color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host "  $line" -ForegroundColor $color
    Add-Content -Path $Log -Value $line -ErrorAction SilentlyContinue
}

# Load profile
if (-not (Test-Path $Profile)) {
    Write-Log "ERROR: Profile not found: $Profile" "Red"
    exit 1
}

try {
    $profileData = Get-Content $Profile -Raw | ConvertFrom-Json
} catch {
    Write-Log "ERROR: Failed to parse profile JSON: $_" "Red"
    exit 1
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host ("  ║  Profile: {0,-40}║" -f $profileData.name) -ForegroundColor Cyan
Write-Host ("  ║  Device:  {0,-40}║" -f $profileData.device_type) -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($profileData.warning) {
    Write-Log "WARNING: $($profileData.warning)" "Yellow"
}

Write-Log "Profile: $($profileData.name) v$($profileData.version)" "Cyan"
Write-Log "Description: $($profileData.description)" "Gray"

if ($DryRun) {
    Write-Log "DRY RUN MODE - No changes will be applied" "Yellow"
}

# Create pre-apply checkpoint
if (-not $DryRun) {
    Write-Log "Creating pre-apply checkpoint..." "Cyan"
    & cmd /c "`"$ModulesDir\checkpoint.bat`" CREATE `"PreProfile_$($profileData.name)`"" 2>&1 | Out-Null
    Write-Log "Pre-apply checkpoint created" "Green"
}

# Sort tweaks by priority
$tweaks = $profileData.tweaks | Sort-Object priority

Write-Log "Applying $($tweaks.Count) tweaks in priority order..." "Cyan"
Write-Host ""

$success = 0
$failed  = 0

foreach ($tweak in $tweaks) {
    $module = $tweak.module
    $action = ($tweak.action).ToUpper()
    Write-Log "[$($tweak.priority)] Module: $module | Action: $action" "White"

    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would execute: $ModulesDir\$module.bat $action" "DarkGray"
        $success++
        continue
    }

    $modulePath = Join-Path $ModulesDir "$module.bat"
    if (-not (Test-Path $modulePath)) {
        Write-Log "  [SKIP] Module not found: $modulePath" "Yellow"
        continue
    }

    try {
        $result = & cmd /c "`"$modulePath`" $action" 2>&1
        $result | ForEach-Object { Write-Log "  $_" "Gray" }
        Write-Log "  [OK] $module.$action completed" "Green"
        $success++
    } catch {
        Write-Log "  [ERROR] $module.$action failed: $_" "Red"
        $failed++
    }

    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Log "Profile applied: $success succeeded, $failed failed" "Cyan"

# Estimated gains
if ($profileData.estimated_gains) {
    Write-Host ""
    Write-Host "  ESTIMATED PERFORMANCE GAINS:" -ForegroundColor Green
    $profileData.estimated_gains.PSObject.Properties | ForEach-Object {
        Write-Host ("    {0,-25} {1}" -f ($_.Name + ":"), $_.Value) -ForegroundColor Green
    }
}

# Create post-apply checkpoint
if (-not $DryRun) {
    Write-Log "Creating post-apply checkpoint..." "Cyan"
    & cmd /c "`"$ModulesDir\checkpoint.bat`" CREATE `"PostProfile_$($profileData.name)`"" 2>&1 | Out-Null
    Write-Log "Post-apply checkpoint created" "Green"
}

if ($profileData.restart_required) {
    Write-Host ""
    Write-Host "  *** RESTART REQUIRED for all changes to take effect ***" -ForegroundColor Yellow
}

Write-Log "Apply complete. Log: $Log" "Cyan"
