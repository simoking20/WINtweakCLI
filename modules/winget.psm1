<#
.SYNOPSIS  WinGet and Chocolatey abstraction module.
#>

function Get-WTUPackageManager {
    $wg = $null -ne (Get-Command winget -EA SilentlyContinue)
    $ch = $null -ne (Get-Command choco  -EA SilentlyContinue)
    return @{ WinGet=$wg; Choco=$ch }
}

function Install-WTUApp {
    param([string]$WinGetId, [string]$ChocoId = '')
    $pm = Get-WTUPackageManager
    if ($pm.WinGet -and $WinGetId) {
        winget install --id $WinGetId --silent --accept-package-agreements --accept-source-agreements 2>&1
        return $true
    } elseif ($pm.Choco -and $ChocoId) {
        choco install $ChocoId -y 2>&1
        return $true
    }
    return $false
}

function Uninstall-WTUApp {
    param([string]$WinGetId)
    $pm = Get-WTUPackageManager
    if ($pm.WinGet -and $WinGetId) {
        winget uninstall --id $WinGetId --silent --accept-source-agreements 2>&1
        return $true
    }
    return $false
}

Export-ModuleMember -Function Get-WTUPackageManager, Install-WTUApp, Uninstall-WTUApp
