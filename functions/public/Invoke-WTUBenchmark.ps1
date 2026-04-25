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

    # Defer Add-Type inside function — safe when compiled inline
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
