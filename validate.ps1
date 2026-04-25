# validate.ps1 - Check all critical bat files for common issues
$dir = "d:\Developeing side\WIN_twake_cli\WinTweakCLI"
$issues = @()

# 1. Check all expected files exist
$expected = @(
    "wtweak.bat",
    "modules\_init.bat","modules\utils.bat","modules\checkpoint.bat",
    "modules\checkpoint_engine.ps1","modules\timer.bat","modules\timer_helper.ps1",
    "modules\nvidia.bat","modules\amd.bat","modules\gpu_memory.bat",
    "modules\power.bat","modules\thermal.bat","modules\process.bat",
    "modules\network.bat","modules\registry.bat","modules\services.bat",
    "modules\memory.bat","modules\input.bat","modules\backup.bat","modules\system.bat",
    "scripts\monitor.ps1","scripts\apply_profile.ps1","scripts\benchmark.ps1",
    "config\profiles\desktop_ultimate.json","config\profiles\laptop_balanced.json",
    "config\profiles\esports_competitive.json","config\profiles\minimal_debloat.json"
)
foreach ($f in $expected) {
    $p = Join-Path $dir $f
    if (-not (Test-Path $p)) { $issues += "MISSING: $f" }
    else { Write-Host "OK: $f" -ForegroundColor Green }
}

# 2. Check JSON profiles are valid
$profiles = Get-ChildItem "$dir\config\profiles\*.json"
foreach ($p in $profiles) {
    try { $null = Get-Content $p.FullName -Raw | ConvertFrom-Json; Write-Host "JSON OK: $($p.Name)" -ForegroundColor Green }
    catch { $issues += "INVALID JSON: $($p.Name)" }
}

# 3. Check bat files for wmic (still remaining)
$bats = Get-ChildItem "$dir\modules\*.bat"
foreach ($b in $bats) {
    $c = Get-Content $b.FullName -Raw
    if ($c -match 'wmic os get localdatetime') {
        $issues += "WMIC TIMESTAMP REMAINING: $($b.Name)"
    }
}

# 4. Check timer_helper.ps1 is referenced in timer.bat
$timerBat = Get-Content "$dir\modules\timer.bat" -Raw
if ($timerBat -match 'timer_helper\.ps1') { Write-Host "OK: timer.bat references timer_helper.ps1" -ForegroundColor Green }
else { $issues += "timer.bat does NOT reference timer_helper.ps1" }

# 5. Check checkpoint.bat no longer uses shift before args
$cpBat = Get-Content "$dir\modules\checkpoint.bat" -Raw
if ($cpBat -match 'ARG2') { Write-Host "OK: checkpoint.bat uses ARG2 pattern" -ForegroundColor Green }
else { $issues += "checkpoint.bat missing ARG2 fix" }

# Summary
Write-Host ""
if ($issues.Count -eq 0) {
    Write-Host "==> ALL CHECKS PASSED" -ForegroundColor Green
} else {
    Write-Host "==> ISSUES FOUND:" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Yellow }
}
