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
