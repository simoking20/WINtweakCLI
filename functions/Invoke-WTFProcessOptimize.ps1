# =============================================================
# Invoke-WTFProcessOptimize.ps1 - WinTweak CLI v3.0
# CPU affinity and core isolation for gaming
# =============================================================

function Invoke-WTFProcessOptimize {
    param(
        [switch]$CoreIsolation,
        [switch]$CoreIsolationOff,
        [ValidateSet("High","Above Normal","Normal","Below Normal","Low")]
        [string]$GamePriority = "Normal"
    )

    if ($CoreIsolation) {
        Write-Host "[*] Applying CPU core isolation for gaming..." -ForegroundColor Cyan

        $logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($logicalCores -lt 4) {
            Write-Warning "Less than 4 logical cores detected. Core isolation skipped."
            return
        }

        # Reserve core 0 for OS/background, game gets cores 1..N-1
        # Affinity mask: all bits set except bit 0
        $gamingMask = ([Math]::Pow(2, $logicalCores) - 1) -band (-bnot 1)
        $osMask     = 1   # only core 0 for system tasks

        # Apply to non-critical system processes
        $sysProcNames = @("svchost","lsass","csrss","smss","wininit","services","System")
        Get-Process | Where-Object { $sysProcNames -contains $_.ProcessName } | ForEach-Object {
            try {
                $_.ProcessorAffinity = $osMask
            } catch { }
        }
        Write-Host "  [+] OS processes pinned to core 0 (affinity: 0x$('{0:X}' -f $osMask))" -ForegroundColor Green

        # Set registry hint for future processes
        $gamePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $gamePath)) { New-Item -Path $gamePath -Force | Out-Null }
        Set-ItemProperty -Path $gamePath -Name "Affinity"           -Value $gamingMask -Type DWord -Force
        Set-ItemProperty -Path $gamePath -Name "Priority"           -Value 6            -Type DWord -Force
        Set-ItemProperty -Path $gamePath -Name "Scheduling Category"-Value "High"        -Type String -Force
        Write-Host "  [+] Game scheduling category: High, Priority: 6" -ForegroundColor Green
        Write-Host "  [+] Gaming affinity mask: 0x$('{0:X}' -f $gamingMask)" -ForegroundColor Green
        Write-Host "[+] Core isolation applied" -ForegroundColor Green
    }
    elseif ($CoreIsolationOff) {
        Write-Host "[*] Removing core isolation overrides..." -ForegroundColor Cyan

        $logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        $fullMask = [Math]::Pow(2, $logicalCores) - 1

        Get-Process | ForEach-Object {
            try { $_.ProcessorAffinity = $fullMask } catch { }
        }

        $gamePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        Set-ItemProperty -Path $gamePath -Name "Priority"            -Value 2       -Type DWord  -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamePath -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gamePath -Name "Affinity" -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Core isolation removed. All processes use full CPU." -ForegroundColor Green
    }

    # Apply priority to detected game processes
    if ($GamePriority -ne "Normal") {
        $priorityLevel = switch ($GamePriority) {
            "High"         { [System.Diagnostics.ProcessPriorityClass]::High }
            "Above Normal" { [System.Diagnostics.ProcessPriorityClass]::AboveNormal }
            "Normal"       { [System.Diagnostics.ProcessPriorityClass]::Normal }
            "Below Normal" { [System.Diagnostics.ProcessPriorityClass]::BelowNormal }
            "Low"          { [System.Diagnostics.ProcessPriorityClass]::Idle }
        }
        # Raise known game engine process names
        $gameHints = @("cs2","csgo","valorant","fortnite","apex","r5apex","LeagueOfLegends","VALORANT-Win64-Shipping","BeamNG","EscapeFromTarkov","RainbowSix")
        Get-Process | Where-Object { $gameHints -contains $_.ProcessName } | ForEach-Object {
            try {
                $_.PriorityClass = $priorityLevel
                Write-Host "  [+] $($_.ProcessName) priority set to $GamePriority" -ForegroundColor Green
            } catch { }
        }
    }
}
