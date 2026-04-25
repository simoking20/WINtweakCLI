function Invoke-WTUGamingMode {
<#
.SYNOPSIS  Applies or undoes a gaming performance mode from gaming.json.
.PARAMETER ModeName  Key name from gaming.json (e.g. WTFModeCompetitiveStable).
.PARAMETER Config    Parsed gaming.json object.
.PARAMETER Undo      If specified, runs UndoScript and restores OriginalValues.
.PARAMETER Force     Skips confirmation prompt.
.EXAMPLE  Invoke-WTUGamingMode -ModeName WTFModeCompetitiveStable -Config $sync.configs.gaming
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $ModeName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Undo,
        [switch]$Force
    )

    $mode = $Config.$ModeName
    if (-not $mode) { throw "Gaming mode not found: $ModeName" }

    $action = if ($Undo) { "Undo" } else { "Apply" }

    Write-Host ""
    Write-Host "  [$action] $($mode.Content)" -ForegroundColor Cyan
    if ($mode.Description) { Write-Host "  $($mode.Description)" -ForegroundColor Gray }
    if ($mode.EstimatedImpact) {
        $mode.EstimatedImpact.PSObject.Properties | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor DarkGray
        }
    }
    if ($mode.Warning) {
        Write-Host ""
        Write-Host "  [WARN] $($mode.Warning)" -ForegroundColor Yellow
    }
    if ($mode.RestartRequired -and -not $Undo) {
        Write-Host "  [INFO] Restart required after applying this mode." -ForegroundColor Yellow
    }

    if (-not $Force) {
        $confirm = Read-Host "`n  Confirm? (YES to proceed)"
        if ($confirm -ne "YES") {
            Write-Host "  Cancelled." -ForegroundColor Gray
            return
        }
    }

    # Auto-checkpoint before applying (not for undo)
    if (-not $Undo) {
        Write-Host "  [Checkpoint] Creating safety checkpoint..." -ForegroundColor DarkCyan
        Invoke-WTURollback -Action Create -Name "Before_$ModeName"
    }

    Invoke-WTUSafeExecution -TweakName $ModeName -ScriptBlock {

        if (-not $Undo) {
            # Registry
            foreach ($reg in $mode.Registry) {
                Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type
            }
            # Services
            foreach ($svc in $mode.Service) {
                try { Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction SilentlyContinue } catch {}
            }
            # InvokeScript
            foreach ($cmd in $mode.InvokeScript) {
                Invoke-Expression $cmd
            }
        } else {
            # Restore registry
            foreach ($reg in $mode.Registry) {
                if ($null -ne $reg.OriginalValue) {
                    Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.OriginalValue -Type $reg.Type
                }
            }
            # Restore services
            foreach ($svc in $mode.Service) {
                if ($svc.OriginalType) {
                    try { Set-Service -Name $svc.Name -StartupType $svc.OriginalType -ErrorAction SilentlyContinue } catch {}
                }
            }
            # UndoScript
            foreach ($cmd in $mode.UndoScript) {
                Invoke-Expression $cmd
            }
        }
    }

    Write-Host ""
    Write-Host "  [+] $($mode.Content) $action complete." -ForegroundColor Green
    Write-WTULog -Action "GamingMode" -Tweak $ModeName -After $action -Success $true
}
