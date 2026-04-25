# =============================================================
# Invoke-WTFBenchmark.ps1 - WinTweak CLI v3.0
# Before/after performance snapshot: latency, thermals, memory
# =============================================================

function Invoke-WTFBenchmark {
    param(
        [string]$CheckpointId,
        [switch]$Before,
        [switch]$After
    )

    Write-Host "[*] WinTweak CLI v3.0 - Running Benchmark (approx 10s)..." -ForegroundColor Cyan

    $results = @{
        Timestamp = Get-Date -Format "o"
        Phase     = if ($Before) { "Before" } elseif ($After) { "After" } else { "Current" }
        System    = @{
            CPU     = (Get-CimInstance Win32_Processor).Name
            GPU     = (Get-CimInstance Win32_VideoController).Name
            RAM_GB  = [math]::Round((Get-CimInstance Win32_PhysicalMemory |
                       Measure-Object Capacity -Sum).Sum / 1GB, 2)
            Windows = [System.Environment]::OSVersion.VersionString
        }
        Metrics   = @{}
    }

    # --- Timer resolution detection ---
    $timerProc = Get-Process | Where-Object { $_.ProcessName -like "*timer*" }
    $results.Metrics.TimerResolution = if ($timerProc) { "0.5ms (Active)" } else { "15.6ms (Default)" }

    # --- GPU metrics ---
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        try {
            $results.Metrics.GPU = @{
                Temperature_C      = [int](nvidia-smi --query-gpu=temperature.gpu       --format=csv,noheader,nounits).Trim()
                Clock_MHz          = [int](nvidia-smi --query-gpu=clocks.gr             --format=csv,noheader,nounits).Trim()
                PowerDraw_W        = [decimal](nvidia-smi --query-gpu=power.draw        --format=csv,noheader,nounits).Trim()
                PowerLimit_W       = [decimal](nvidia-smi --query-gpu=power.limit       --format=csv,noheader,nounits).Trim()
                Utilization_Pct    = [int](nvidia-smi --query-gpu=utilization.gpu       --format=csv,noheader,nounits).Trim()
                Locked             = (nvidia-smi --query-gpu=clocks.gr --format=csv,noheader) -match "Locked"
            }
        } catch {
            $results.Metrics.GPU = @{ Error = "nvidia-smi query failed: $_" }
        }
    }

    # --- CPU load (5 samples x 200ms) ---
    $cpuLoads = @()
    for ($i = 0; $i -lt 5; $i++) {
        $cpuLoads += (Get-CimInstance Win32_Processor | Select-Object -First 1).LoadPercentage
        Start-Sleep -Milliseconds 200
    }
    $results.Metrics.CPU = @{
        AverageLoad_Pct = [math]::Round(($cpuLoads | Measure-Object -Average).Average, 1)
        MaxLoad_Pct     = ($cpuLoads | Measure-Object -Maximum).Maximum
    }

    # --- Memory ---
    $os = Get-CimInstance Win32_OperatingSystem
    $results.Metrics.Memory = @{
        Used_GB    = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        Total_GB   = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        Used_Pct   = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    }

    # --- Network latency ---
    $pingResults = @()
    foreach ($target in @("8.8.8.8","1.1.1.1")) {
        try {
            $p = Test-Connection $target -Count 4 -ErrorAction Stop
            $pingResults += @{ Target = $target; AvgMs = [math]::Round(($p | Measure-Object ResponseTime -Average).Average, 1) }
        } catch {
            $pingResults += @{ Target = $target; AvgMs = -1 }
        }
    }
    $validPings = $pingResults | Where-Object { $_.AvgMs -gt 0 }
    $results.Metrics.Network = @{
        LatencyTests   = $pingResults
        AverageLatency = if ($validPings) { [math]::Round(($validPings | Measure-Object AvgMs -Average).Average, 1) } else { -1 }
    }

    # --- Estimated input lag ---
    $timerLag = if ($results.Metrics.TimerResolution -match "0.5") { 0.5 } else { 15.6 }
    $gpuLag   = if ($results.Metrics.GPU.Locked)                   { 2.0 } else { 4.0 }
    $totalLag = [math]::Round($timerLag + $gpuLag + 3.0 + 4.0, 1)
    $results.Metrics.EstimatedInputLag = @{
        TotalEstimated_ms = $totalLag
        Breakdown         = "Timer ${timerLag}ms + GPU ${gpuLag}ms + System 3ms + Display 4ms"
    }

    # --- Thermal score ---
    $temp = if ($results.Metrics.GPU.Temperature_C) { $results.Metrics.GPU.Temperature_C } else { 0 }
    $thermalScore = if ($temp -lt 65) { "Excellent" } elseif ($temp -lt 75) { "Good" } elseif ($temp -lt 85) { "Caution" } else { "Critical" }
    $results.Metrics.Thermal = @{ GPU_Temp_C = $temp; Sustainability = $thermalScore }

    # --- Save to disk ---
    $benchDir  = "$env:LOCALAPPDATA\WinTweakCLI\Benchmarks"
    if (-not (Test-Path $benchDir)) { New-Item -ItemType Directory -Path $benchDir -Force | Out-Null }
    $filepath  = "$benchDir\benchmark_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $results | ConvertTo-Json -Depth 10 | Set-Content $filepath

    # --- Display results ---
    Write-Host ""
    Write-Host "  === BENCHMARK RESULTS ===" -ForegroundColor Cyan
    Write-Host "  Phase : $($results.Phase)   Time: $($results.Timestamp)" -ForegroundColor White
    Write-Host "  Timer : $($results.Metrics.TimerResolution)" -ForegroundColor White
    if ($results.Metrics.GPU.Clock_MHz) {
        $tc = if ($temp -gt 80) { "Red" } elseif ($temp -gt 70) { "Yellow" } else { "Green" }
        Write-Host "  GPU   : Temp=$($results.Metrics.GPU.Temperature_C)C  Clock=$($results.Metrics.GPU.Clock_MHz)MHz  Power=$($results.Metrics.GPU.PowerDraw_W)/$($results.Metrics.GPU.PowerLimit_W)W  Util=$($results.Metrics.GPU.Utilization_Pct)%" -ForegroundColor $tc
    }
    Write-Host "  CPU   : Avg=$($results.Metrics.CPU.AverageLoad_Pct)%  Peak=$($results.Metrics.CPU.MaxLoad_Pct)%" -ForegroundColor White
    Write-Host "  RAM   : $($results.Metrics.Memory.Used_GB)/$($results.Metrics.Memory.Total_GB) GB ($($results.Metrics.Memory.Used_Pct)%)" -ForegroundColor White
    Write-Host "  Net   : Avg latency $($results.Metrics.Network.AverageLatency)ms" -ForegroundColor White
    $lagColor = if ($totalLag -lt 10) { "Green" } elseif ($totalLag -lt 15) { "Yellow" } else { "Red" }
    Write-Host "  Input : ~${totalLag}ms  ($($results.Metrics.EstimatedInputLag.Breakdown))" -ForegroundColor $lagColor
    $thermColor = if ($thermalScore -eq "Critical") { "Red" } elseif ($thermalScore -eq "Caution") { "Yellow" } else { "Green" }
    Write-Host "  Therm : $thermalScore (${temp}C)" -ForegroundColor $thermColor
    Write-Host ""
    Write-Host "  [+] Saved: $filepath" -ForegroundColor Green
    Write-Host ""

    return $results
}
