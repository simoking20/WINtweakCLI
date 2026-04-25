function Invoke-WTUAppManager {
<#
.SYNOPSIS  Installs or uninstalls applications defined in applications.json.
.PARAMETER AppName   Key name (e.g. WPFInstallChrome) or array of names.
.PARAMETER Config    Parsed applications.json object.
.PARAMETER Uninstall If specified, uninstalls instead of installing.
.EXAMPLE  Invoke-WTUAppManager -AppName @('WPFInstallChrome','WPFInstallDiscord') -Config $sync.configs.applications
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]     $AppName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Uninstall
    )

    $action = if ($Uninstall) { "Uninstall" } else { "Install" }

    # Check WinGet availability
    $hasWinGet = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $hasChoco  = $null -ne (Get-Command choco  -ErrorAction SilentlyContinue)

    if (-not $hasWinGet -and -not $hasChoco) {
        Write-Warning "Neither WinGet nor Chocolatey is available. Cannot manage apps."
        return
    }

    foreach ($name in $AppName) {
        $app = $Config.$name
        if (-not $app) { Write-Warning "App not found in config: $name"; continue }

        Write-Host "[$action] $($app.Content)..." -ForegroundColor Cyan

        $success = $false

        # Try WinGet first
        if ($hasWinGet -and $app.winget) {
            try {
                if ($Uninstall) {
                    winget uninstall --id $app.winget --silent --accept-source-agreements 2>&1 | Out-Null
                } else {
                    winget install --id $app.winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                }
                $success = $true
                Write-Host "  [OK] $($app.Content) via WinGet" -ForegroundColor Green
            } catch { Write-Warning "WinGet failed for $($app.Content): $_" }
        }

        # Chocolatey fallback
        if (-not $success -and $hasChoco -and $app.choco -and -not $Uninstall) {
            try {
                choco install $app.choco -y 2>&1 | Out-Null
                $success = $true
                Write-Host "  [OK] $($app.Content) via Chocolatey" -ForegroundColor Green
            } catch { Write-Warning "Choco failed: $_" }
        }

        if (-not $success) { Write-Warning "  [FAIL] Could not $action $($app.Content)" }
        Write-WTULog -Action "AppManager" -Tweak $name -After $action -Success $success
    }
}
