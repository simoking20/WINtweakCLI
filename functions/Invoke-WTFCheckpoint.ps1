# =============================================================
# Invoke-WTFCheckpoint.ps1 - WinTweak CLI v3.0
# Checkpoint CRUD: Create / Restore / List / Delete
# =============================================================

function Invoke-WTFCheckpoint {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Create","Restore","List","Delete")]
        [string]$Action,
        [string]$Name,
        [string]$Id,
        [switch]$Interactive
    )

    $checkpointDir = "$env:LOCALAPPDATA\WinTweakCLI\Checkpoints"
    $indexFile     = "$checkpointDir\index.json"
    if (-not (Test-Path $checkpointDir)) { New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null }

    $index = @()
    if (Test-Path $indexFile) { $index = Get-Content $indexFile -Raw | ConvertFrom-Json }

    switch ($Action) {
        # ---------------------------------------------------------
        "Create" {
            $timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
            $checkpointId = "$($index.Count + 1)_$timestamp"
            $cpPath       = "$checkpointDir\checkpoint_$checkpointId"
            New-Item -ItemType Directory -Path $cpPath -Force | Out-Null

            Write-Host "[*] Creating checkpoint $checkpointId..." -ForegroundColor Cyan

            # Registry
            reg export HKLM "$cpPath\hklm.reg" /y | Out-Null
            reg export HKCU "$cpPath\hkcu.reg" /y | Out-Null
            Write-Host "  [+] Registry backed up" -ForegroundColor Green

            # Services
            Get-Service | Select-Object Name, Status, StartType |
                ConvertTo-Json | Set-Content "$cpPath\services.json"
            Write-Host "  [+] Services state saved" -ForegroundColor Green

            # Power plan
            $activePlan = (powercfg /getactivescheme).Split()[3]
            @{ ActivePlan = $activePlan } | ConvertTo-Json | Set-Content "$cpPath\powerplan.json"
            Write-Host "  [+] Power plan saved" -ForegroundColor Green

            # GPU state (NVIDIA only)
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                $gpuState = @{
                    Clocks      = (nvidia-smi --query-gpu=clocks.gr,clocks.mem --format=csv,noheader)
                    PowerLimit  = (nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits)
                    Persistence = (nvidia-smi --query-gpu=persistence_mode --format=csv,noheader)
                }
                $gpuState | ConvertTo-Json | Set-Content "$cpPath\gpu_state.json"
                Write-Host "  [+] GPU state saved" -ForegroundColor Green
            }

            # Network
            Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway |
                ConvertTo-Json | Set-Content "$cpPath\network.json"
            Write-Host "  [+] Network config saved" -ForegroundColor Green

            # Metadata
            $metadata = @{
                Id             = $checkpointId
                Name           = $Name
                Timestamp      = Get-Date -Format "o"
                WindowsVersion = [System.Environment]::OSVersion.VersionString
                Hardware       = @{
                    CPU    = (Get-CimInstance Win32_Processor).Name
                    GPU    = (Get-CimInstance Win32_VideoController).Name
                    RAM_GB = [math]::Round((Get-CimInstance Win32_PhysicalMemory |
                               Measure-Object Capacity -Sum).Sum / 1GB, 2)
                }
            }
            $metadata | ConvertTo-Json -Depth 5 | Set-Content "$cpPath\metadata.json"

            $index += $metadata
            $index | ConvertTo-Json -Depth 5 | Set-Content $indexFile
            Write-Host "[+] Checkpoint $checkpointId created successfully" -ForegroundColor Green
        }

        # ---------------------------------------------------------
        "Restore" {
            if ($Interactive) {
                Invoke-WTFCheckpoint -Action List
                $Id = Read-Host "`nEnter checkpoint ID to restore"
            }
            $cpPath = "$checkpointDir\checkpoint_$Id"
            if (-not (Test-Path $cpPath)) { throw "Checkpoint $Id not found" }

            Write-Host "[!] WARNING: About to restore system to checkpoint $Id" -ForegroundColor Yellow
            if ((Read-Host "Type 'YES' to confirm") -ne "YES") {
                Write-Host "Restore cancelled." -ForegroundColor Red
                return
            }

            Write-Host "[*] Restoring checkpoint $Id..." -ForegroundColor Cyan
            reg import "$cpPath\hklm.reg" | Out-Null
            reg import "$cpPath\hkcu.reg" | Out-Null
            Write-Host "  [+] Registry restored" -ForegroundColor Green

            (Get-Content "$cpPath\services.json" | ConvertFrom-Json) | ForEach-Object {
                Set-Service -Name $_.Name -StartupType $_.StartType -ErrorAction SilentlyContinue
            }
            Write-Host "  [+] Services restored" -ForegroundColor Green

            $plan = (Get-Content "$cpPath\powerplan.json" | ConvertFrom-Json).ActivePlan
            powercfg -setactive $plan | Out-Null
            Write-Host "  [+] Power plan restored" -ForegroundColor Green

            if (Test-Path "$cpPath\gpu_state.json") {
                if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                    nvidia-smi --lock-gpu-clocks=0,0    | Out-Null
                    nvidia-smi --lock-memory-clocks=0,0 | Out-Null
                }
                Write-Host "  [+] GPU state restored (clocks unlocked)" -ForegroundColor Green
            }
            Write-Host "[+] Checkpoint $Id restored. Restart recommended." -ForegroundColor Green
        }

        # ---------------------------------------------------------
        "List" {
            if ($index.Count -eq 0) {
                Write-Host "No checkpoints found." -ForegroundColor Yellow
                return
            }
            Write-Host "`n=== SAVED CHECKPOINTS ===" -ForegroundColor Cyan
            foreach ($cp in $index) {
                Write-Host "`n  [$($cp.Id)]  $($cp.Name)" -ForegroundColor Green
                Write-Host "      Created : $($cp.Timestamp)"    -ForegroundColor Gray
                Write-Host "      Windows : $($cp.WindowsVersion)" -ForegroundColor Gray
                Write-Host "      CPU     : $($cp.Hardware.CPU)"   -ForegroundColor Gray
                Write-Host "      GPU     : $($cp.Hardware.GPU)"   -ForegroundColor Gray
                Write-Host "      RAM     : $($cp.Hardware.RAM_GB) GB" -ForegroundColor Gray
            }
            Write-Host ""
        }

        # ---------------------------------------------------------
        "Delete" {
            if (-not $Id) { throw "Checkpoint ID is required for Delete." }
            $cpPath = "$checkpointDir\checkpoint_$Id"
            if (Test-Path $cpPath) {
                Remove-Item $cpPath -Recurse -Force
                $index = $index | Where-Object { $_.Id -ne $Id }
                $index | ConvertTo-Json -Depth 5 | Set-Content $indexFile
                Write-Host "[+] Checkpoint $Id deleted" -ForegroundColor Green
            } else {
                Write-Warning "Checkpoint $Id not found."
            }
        }
    }
}
