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

Export-ModuleMember -Function Test-WTUNVIDIAAvailable, Get-WTUNVIDIAInfo, Invoke-WTUNVIDIALockClocks, Invoke-WTUNVIDIAUnlockClocks, Set-WTUNVIDIAPowerLimit, Enable-WTUNVIDIAPersistence
