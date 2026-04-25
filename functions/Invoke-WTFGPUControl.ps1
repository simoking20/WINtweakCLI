# =============================================================
# Invoke-WTFGPUControl.ps1 - WinTweak CLI v3.0
# NVIDIA / AMD / Intel GPU tuning
# =============================================================

function Invoke-WTFGPUControl {
    param(
        [Parameter(Mandatory)][ValidateSet("NVIDIA","AMD","Intel")][string]$Vendor,
        [int]$LockClocks,
        [int]$MemoryClocks,
        [int]$PowerLimitPercent,
        [switch]$UnlockClocks,
        [switch]$PersistenceMode,
        [switch]$AdaptivePower,
        [switch]$PowerSaveMode
    )

    Write-Host "[*] Applying GPU settings for $Vendor..." -ForegroundColor Cyan

    switch ($Vendor) {
        "NVIDIA" {
            if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
                throw "nvidia-smi not found. Ensure NVIDIA drivers are installed."
            }
            if ($PersistenceMode) {
                nvidia-smi --persistence-mode=1 | Out-Null
                Write-Host "  [+] Persistence mode enabled" -ForegroundColor Green
            }
            if ($LockClocks) {
                nvidia-smi --lock-gpu-clocks=$LockClocks,$LockClocks | Out-Null
                Write-Host "  [+] GPU clocks locked at ${LockClocks}MHz" -ForegroundColor Green
            }
            if ($MemoryClocks) {
                nvidia-smi --lock-memory-clocks=$MemoryClocks,$MemoryClocks | Out-Null
                Write-Host "  [+] Memory clocks locked at ${MemoryClocks}MHz" -ForegroundColor Green
            }
            if ($PowerLimitPercent) {
                $maxPower = [decimal](nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits).Trim()
                $target   = [math]::Floor($maxPower * $PowerLimitPercent / 100)
                nvidia-smi --power-limit=$target | Out-Null
                Write-Host "  [+] Power limit set to ${PowerLimitPercent}% (${target}W)" -ForegroundColor Green
            }
            if ($UnlockClocks) {
                nvidia-smi --lock-gpu-clocks=0,0      | Out-Null
                nvidia-smi --lock-memory-clocks=0,0   | Out-Null
                Write-Host "  [+] GPU clocks unlocked" -ForegroundColor Green
            }
            if ($AdaptivePower) {
                $defaultLimit = (nvidia-smi --query-gpu=power.default_limit --format=csv,noheader,nounits).Trim()
                nvidia-smi --power-limit=$defaultLimit | Out-Null
                nvidia-smi --lock-gpu-clocks=0,0       | Out-Null
                Write-Host "  [+] Adaptive power mode enabled" -ForegroundColor Green
            }
            if ($PowerSaveMode) {
                $maxPower = [decimal](nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits).Trim()
                $target   = [math]::Floor($maxPower * 50 / 100)
                nvidia-smi --power-limit=$target | Out-Null
                nvidia-smi --lock-gpu-clocks=0,0 | Out-Null
                Write-Host "  [+] Power save mode enabled (${target}W)" -ForegroundColor Green
            }
        }
        "AMD" {
            $amdKey  = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
            $gpuKeys = Get-ChildItem $amdKey -ErrorAction SilentlyContinue |
                       Where-Object { $_.PSChildName -match '^\d{4}$' }
            foreach ($key in $gpuKeys) {
                if ($LockClocks)        { Set-ItemProperty -Path $key.PSPath -Name "PPDPEnable" -Value 0 -ErrorAction SilentlyContinue }
                if ($PowerLimitPercent) { Set-ItemProperty -Path $key.PSPath -Name "PPDPEnable" -Value 0 -ErrorAction SilentlyContinue }
            }
            Set-ItemProperty "HKLM:\SOFTWARE\AMD\CN" -Name "GamingModeAntiLag" -Value 1 -ErrorAction SilentlyContinue
            Write-Host "  [+] AMD Anti-Lag enabled" -ForegroundColor Green
        }
        "Intel" {
            Set-ItemProperty "HKLM:\SOFTWARE\Intel\Arc\Control" -Name "LowLatencyMode" -Value 1 -ErrorAction SilentlyContinue
            Write-Host "  [+] Intel Low Latency mode enabled" -ForegroundColor Green
        }
    }
    Write-Host "[+] GPU configuration applied" -ForegroundColor Green
}
