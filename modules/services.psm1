<#
.SYNOPSIS  Service management module with state capture and restoration.
#>

function Get-WTUServiceState {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) { return @{ Status=$svc.Status; StartType=$svc.StartType } }
    return $null
}

function Set-WTUServiceStartup {
    param([string]$Name, [string]$StartupType)
    try { Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop; return $true }
    catch { Write-Warning "Cannot set $Name to $StartupType : $_"; return $false }
}

function Stop-WTUService { param([string]$Name); Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
function Start-WTUService { param([string]$Name); Start-Service -Name $Name -ErrorAction SilentlyContinue }

Export-ModuleMember -Function Get-WTUServiceState, Set-WTUServiceStartup, Stop-WTUService, Start-WTUService
