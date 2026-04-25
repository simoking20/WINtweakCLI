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

Export-ModuleMember -Function Set-WTUProcessGamingPriority, Enable-WTUCoreIsolation, Disable-WTUCoreIsolation
