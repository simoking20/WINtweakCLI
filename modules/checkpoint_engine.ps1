# checkpoint_engine.ps1 - PowerShell comparison engine for checkpoints
param(
    [switch]$Compare,
    [int]$CP1,
    [int]$CP2,
    [string]$BaseDir = (Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent)
)

$CpDir  = Join-Path $BaseDir "config\checkpoints"
$Index  = Join-Path $CpDir "index.txt"

function Get-CheckpointPath {
    param([int]$num)
    if (-not (Test-Path $Index)) { return $null }
    $lines = Get-Content $Index -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 2 -and $parts[0].Trim() -eq "$num") {
            return Join-Path $CpDir $parts[1].Trim()
        }
    }
    return $null
}

function Load-Metadata {
    param([string]$cpPath)
    $metaFile = Join-Path $cpPath "metadata.json"
    if (Test-Path $metaFile) {
        try {
            return Get-Content $metaFile -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Format-FileSize {
    param([long]$bytes)
    if ($bytes -gt 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    if ($bytes -gt 1KB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

if ($Compare) {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   CHECKPOINT COMPARISON: #$CP1  vs  #$CP2" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan

    $path1 = Get-CheckpointPath -num $CP1
    $path2 = Get-CheckpointPath -num $CP2

    if (-not $path1 -or -not (Test-Path $path1)) {
        Write-Host "  [ERROR] Checkpoint #$CP1 not found." -ForegroundColor Red
        exit 1
    }
    if (-not $path2 -or -not (Test-Path $path2)) {
        Write-Host "  [ERROR] Checkpoint #$CP2 not found." -ForegroundColor Red
        exit 1
    }

    $meta1 = Load-Metadata -cpPath $path1
    $meta2 = Load-Metadata -cpPath $path2

    Write-Host ""
    Write-Host "  FIELD            | CHECKPOINT #$CP1          | CHECKPOINT #$CP2"
    Write-Host "  -----------------+---------------------------+---------------------------"

    $fields = @('name','timestamp','device_type','gpu_vendor','user','computer')
    foreach ($f in $fields) {
        $v1 = if ($meta1) { $meta1.$f } else { "N/A" }
        $v2 = if ($meta2) { $meta2.$f } else { "N/A" }
        $v1s = "$v1".PadRight(26)
        $v2s = "$v2".PadRight(26)
        $color = if ($v1 -ne $v2) { "Yellow" } else { "White" }
        Write-Host ("  {0,-16} | {1,-26} | {2,-26}" -f $f.PadRight(16), $v1s, $v2s) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  REGISTRY FILE SIZES:" -ForegroundColor Cyan
    foreach ($regFile in @('hklm.reg', 'hkcu.reg')) {
        $f1 = Join-Path $path1 $regFile
        $f2 = Join-Path $path2 $regFile
        $s1 = if (Test-Path $f1) { (Get-Item $f1).Length } else { 0 }
        $s2 = if (Test-Path $f2) { (Get-Item $f2).Length } else { 0 }
        $diff = $s2 - $s1
        $diffStr = if ($diff -gt 0) { "+$(Format-FileSize $diff)" } elseif ($diff -lt 0) { "$(Format-FileSize $diff)" } else { "same" }
        Write-Host ("  {0,-10} | CP#{1}: {2,-12} | CP#{3}: {4,-12} | Diff: {5}" -f `
            $regFile, $CP1, (Format-FileSize $s1), $CP2, (Format-FileSize $s2), $diffStr)
    }

    Write-Host ""
    Write-Host "  NVIDIA STATES:" -ForegroundColor Cyan
    $nv1File = Join-Path $path1 "nvidia_state.txt"
    $nv2File = Join-Path $path2 "nvidia_state.txt"
    $nv1 = if (Test-Path $nv1File) { (Get-Content $nv1File -Raw).Trim() } else { "N/A" }
    $nv2 = if (Test-Path $nv2File) { (Get-Content $nv2File -Raw).Trim() } else { "N/A" }
    Write-Host "  CP#${CP1}: $nv1"
    Write-Host "  CP#${CP2}: $nv2"

    Write-Host ""
    Write-Host "  SERVICE STATES:" -ForegroundColor Cyan
    $svc1File = Join-Path $path1 "services.txt"
    $svc2File = Join-Path $path2 "services.txt"
    $svc1Lines = if (Test-Path $svc1File) { (Get-Content $svc1File).Count } else { 0 }
    $svc2Lines = if (Test-Path $svc2File) { (Get-Content $svc2File).Count } else { 0 }
    Write-Host "  CP#${CP1} service entries: $svc1Lines"
    Write-Host "  CP#${CP2} service entries: $svc2Lines"
    if ($svc1Lines -ne $svc2Lines) {
        Write-Host "  [DIFF] Service state files differ in size ($($svc2Lines - $svc1Lines) lines)" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK]   Service state files appear similar" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
}
