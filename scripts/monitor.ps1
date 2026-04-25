# monitor.ps1 - Real-time system monitor with timer, CPU, GPU stats
param(
    [int]$RefreshMs = 1000,
    [switch]$GameMode
)

# TimerResolution C# interop
$timerTypeDef = @"
using System;
using System.Runtime.InteropServices;
public class TimerMonitor {
    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out uint MinResolution, out uint MaxResolution, out uint CurrentResolution);
}
"@

try {
    Add-Type -TypeDefinition $timerTypeDef -ErrorAction Stop
} catch {
    Write-Warning "Could not load timer resolution API"
}

function Get-TimerResolution {
    try {
        $mn = [uint32]0; $mx = [uint32]0; $cur = [uint32]0
        [TimerMonitor]::NtQueryTimerResolution([ref]$mn, [ref]$mx, [ref]$cur) | Out-Null
        return $cur / 10000.0
    } catch { return -1 }
}

function Get-NvidiaStats {
    try {
        $result = & nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,clocks.gr,clocks.mem,power.draw,memory.used,memory.total `
            --format=csv,noheader,nounits 2>$null
        if ($result) {
            $parts = $result -split ', '
            return @{
                Util    = if ($parts.Count -gt 0) { $parts[0].Trim() + "%" } else { "N/A" }
                Temp    = if ($parts.Count -gt 1) { $parts[1].Trim() + "°C" } else { "N/A" }
                CoreClk = if ($parts.Count -gt 2) { $parts[2].Trim() + " MHz" } else { "N/A" }
                MemClk  = if ($parts.Count -gt 3) { $parts[3].Trim() + " MHz" } else { "N/A" }
                Power   = if ($parts.Count -gt 4) { $parts[4].Trim() + "W" } else { "N/A" }
                VramUsed  = if ($parts.Count -gt 5) { [math]::Round([int]$parts[5].Trim() / 1024, 1).ToString() + " GB" } else { "N/A" }
                VramTotal = if ($parts.Count -gt 6) { [math]::Round([int]$parts[6].Trim() / 1024, 1).ToString() + " GB" } else { "N/A" }
            }
        }
    } catch {}
    return $null
}

# GameMode: set priority and timer
if ($GameMode) {
    Write-Host "  [GAMEMODE] Setting process priority to High..." -ForegroundColor Green
    try {
        $proc = Get-Process -Id $PID
        $proc.PriorityClass = 'High'
    } catch {}
    
    try {
        $timerSet = @"
using System.Runtime.InteropServices;
public class TSet { [DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint d,bool s,out uint c); }
"@
        Add-Type -TypeDefinition $timerSet -ErrorAction Stop
        $c = [uint32]0
        [TSet]::NtSetTimerResolution(5000, $true, [ref]$c) | Out-Null
        Write-Host "  [GAMEMODE] Timer set to $($c/10000.0) ms" -ForegroundColor Green
    } catch {}
}

Write-Host ""
Write-Host "  WinTweak CLI v2.1 - Real-time System Monitor" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to exit" -ForegroundColor DarkGray
Write-Host ""

$hasNvidia = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)

while ($true) {
    $timerMs = Get-TimerResolution
    
    # CPU
    $cpuLoad = (Get-WmiObject -Class Win32_Processor -ErrorAction SilentlyContinue).LoadPercentage
    
    # RAM
    $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramUsedGB   = if ($os) { [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1) } else { 0 }
    $ramTotalGB  = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) } else { 0 }
    $ramPct      = if ($ramTotalGB -gt 0) { [math]::Round($ramUsedGB * 100 / $ramTotalGB, 0) } else { 0 }
    
    # Top 5 CPU processes
    $topProcs = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object CPU -Descending |
        Select-Object -First 5 Name, CPU, WorkingSet64

    # Clear and redraw
    Clear-Host
    
    $now = Get-Date -Format "HH:mm:ss"
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host ("  ║  WinTweak CLI Monitor  [{0}]                        ║" -f $now) -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════╦═══════════════════════════════════╣" -ForegroundColor DarkCyan
    
    # Timer
    $timerColor = if ($timerMs -lt 1.0 -and $timerMs -gt 0) { "Green" } elseif ($timerMs -lt 5.0 -and $timerMs -gt 0) { "Yellow" } else { "Red" }
    $timerStr = if ($timerMs -gt 0) { "$timerMs ms" } else { "N/A" }
    Write-Host ("  ║  TIMER RESOLUTION    ║  {0,-33} ║" -f $timerStr) -ForegroundColor $timerColor

    # CPU
    $cpuStr = "$cpuLoad% Load"
    Write-Host ("  ║  CPU USAGE           ║  {0,-33} ║" -f $cpuStr) -ForegroundColor White

    # RAM
    $ramStr = "$ramUsedGB / $ramTotalGB GB  ($ramPct%)"
    Write-Host ("  ║  MEMORY              ║  {0,-33} ║" -f $ramStr) -ForegroundColor White

    Write-Host "  ╠══════════════════════╩═══════════════════════════════════╣" -ForegroundColor DarkCyan

    # GPU
    if ($hasNvidia) {
        $gpu = Get-NvidiaStats
        if ($gpu) {
            Write-Host "  ║  GPU (NVIDIA)                                             ║" -ForegroundColor DarkCyan
            Write-Host ("  ║    Utilization: {0,-8}  Temp: {1,-8}  Core: {2,-10} ║" -f $gpu.Util, $gpu.Temp, $gpu.CoreClk) -ForegroundColor Green
            Write-Host ("  ║    Memory: {0,-7}/{1,-7}  Power: {2,-8}  MemClk: {3,-6} ║" -f $gpu.VramUsed, $gpu.VramTotal, $gpu.Power, $gpu.MemClk) -ForegroundColor Green
        }
    } else {
        Write-Host "  ║  GPU: NVIDIA not detected (nvidia-smi unavailable)       ║" -ForegroundColor DarkGray
    }

    Write-Host "  ╠═══════════════════════════════════════════════════════════╣" -ForegroundColor DarkCyan
    Write-Host "  ║  TOP PROCESSES (by CPU time)                              ║" -ForegroundColor DarkCyan
    
    foreach ($p in $topProcs) {
        $cpuT = if ($p.CPU) { [math]::Round($p.CPU, 1) } else { 0 }
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
        Write-Host ("  ║    {0,-22} CPU:{1,7}s  RAM:{2,6} MB          ║" -f ($p.Name.Substring(0, [Math]::Min($p.Name.Length, 22))), $cpuT, $memMB) -ForegroundColor Gray
    }

    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  [Ctrl+C to exit]  Refresh: ${RefreshMs}ms" -ForegroundColor DarkGray

    Start-Sleep -Milliseconds $RefreshMs
}
