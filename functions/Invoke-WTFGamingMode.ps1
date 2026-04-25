# =============================================================
# Invoke-WTFGamingMode.ps1 - WinTweak CLI v3.0
# Unified handler: registry, scripts, services, appx
# =============================================================

function Invoke-WTFGamingMode {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][PSObject]$Data,
        [switch]$Apply,
        [switch]$Undo
    )

    $action = if ($Undo) { "Undo" } else { "Apply" }
    Write-Host "[$action] $($Data.Content)" -ForegroundColor Cyan

    # --- Registry ---
    if ($Data.registry) {
        foreach ($reg in $Data.registry) {
            $value = if ($Undo -and $reg.OriginalValue -ne "") { $reg.OriginalValue } else { $reg.Value }
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $value -Type $reg.Type -Force
            Write-Host "  [+] Registry: $($reg.Path)\$($reg.Name) = $value" -ForegroundColor Green
        }
    }

    # --- Scripts ---
    $scriptKey = if ($Undo -and $Data.UndoScript) { "UndoScript" } elseif ($Apply -and $Data.InvokeScript) { "InvokeScript" } else { $null }
    if ($scriptKey) {
        foreach ($script in $Data.$scriptKey) {
            try { Invoke-Expression $script; Write-Host "  [+] Script executed: $script" -ForegroundColor Green }
            catch { Write-Warning "  [!] Script failed: $_" }
        }
    }

    # --- Services ---
    if ($Data.service) {
        foreach ($svc in $Data.service) {
            $targetType = if ($Undo) { $svc.OriginalType } else { $svc.StartupType }
            Set-Service -Name $svc.Name -StartupType $targetType -ErrorAction SilentlyContinue
            Write-Host "  [+] Service: $($svc.Name) -> $targetType" -ForegroundColor Green
        }
    }

    # --- Appx packages ---
    if ($Data.appx -and -not $Undo) {
        foreach ($app in $Data.appx) {
            Get-AppxPackage $app -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Host "  [+] Removed Appx: $app" -ForegroundColor Green
        }
    }

    Write-Host "[+] $($Data.Content) $action completed" -ForegroundColor Green

    # --- Audit log ---
    $logEntry = @{
        Timestamp = Get-Date -Format "o"
        Action    = $action
        Tweak     = $Name
        Content   = $Data.Content
        User      = $env:USERNAME
    }
    $logDir  = "$env:LOCALAPPDATA\WinTweakCLI\Logs"
    $logPath = "$logDir\gaming_$(Get-Date -Format 'yyyyMM').jsonl"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logEntry | ConvertTo-Json -Compress | Add-Content $logPath
}
