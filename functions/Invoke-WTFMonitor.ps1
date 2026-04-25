# =============================================================
# Invoke-WTFMonitor.ps1 - WinTweak CLI v3.0
# Real-time system monitor (GPU / CPU / RAM / Temp)
# Press Ctrl+C to stop.
# =============================================================

function Invoke-WTFMonitor {
    param(
        [int]$RefreshRate = 1000   # milliseconds
    )

    Write-Host "[*] WinTweak CLI v3.0 - Real-time Monitor (Ctrl+C to stop)" -ForegroundColor Cyan
    Write-Host "    Refresh: ${RefreshRate}ms" -ForegroundColor DarkGray

    $gpuVendor = "Unknown"
    if (Get-Command nvidia-smi     -ErrorAction SilentlyContinue) { $gpuVendor = "NVIDIA" }
    elseif (Get-Command amdvbflash -ErrorAction SilentlyContinue) { $gpuVendor = "AMD" }

    while ($true) {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $os  = Get-CimInstance Win32_OperatingSystem
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1

        $usedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)

        $lines = @(
            ""
            "  === WinTweak v3.0 Live Monitor === $(Get-Date -Format 'HH:mm:ss')"
            "  CPU  : $($cpu.Name.Substring(0,[Math]::Min(35,$cpu.Name.Length)))"
            "         Load: $($cpu.LoadPercentage)%"
            "  RAM  : ${usedGB} / ${totalGB} GB"
            "  GPU  : $($gpu.Name.Substring(0,[Math]::Min(35,$gpu.Name.Length)))"
        )

        if ($gpuVendor -eq "NVIDIA") {
            try {
                $nv = (nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,clocks.gr,power.draw,power.limit `
                       --format=csv,noheader,nounits).Split(',')
                $temp   = $nv[0].Trim()
                $util   = $nv[1].Trim()
                $clock  = $nv[2].Trim()
                $draw   = $nv[3].Trim()
                $limit  = $nv[4].Trim()
                $tempColor = if ([int]$temp -gt 84) { "Red" } elseif ([int]$temp -gt 74) { "Yellow" } else { "Green" }
                $lines += "         Temp:  ${temp}C  Util: ${util}%"
                $lines += "         Clock: ${clock}MHz  Power: ${draw}/${limit}W"
            } catch {
                $lines += "         (nvidia-smi query failed)"
            }
        }

        $lines += ""
        Clear-Host
        foreach ($l in $lines) { Write-Host $l }

        Start-Sleep -Milliseconds $RefreshRate
    }
}
