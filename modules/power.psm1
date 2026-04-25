<#
.SYNOPSIS  Power plan management module.
#>

$PLANS = @{
    Balanced       = '381b4222-f694-41f0-9685-ff5bb260df2e'
    HighPerformance= '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    PowerSaver     = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    Ultimate       = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
}

function Get-WTUActivePowerPlan {
    $line = powercfg /getactivescheme 2>&1
    if ($line -match 'GUID: ([0-9a-f-]+)\s+\((.+)\)') {
        return @{ GUID=$Matches[1]; Name=$Matches[2] }
    }
    return $null
}

function Set-WTUPowerPlan {
    param([ValidateSet('Balanced','HighPerformance','PowerSaver','Ultimate')][string]$Plan)
    $guid = $PLANS[$Plan]
    if ($Plan -eq 'Ultimate') {
        powercfg -duplicatescheme $guid 2>&1 | Out-Null
    }
    powercfg -setactive $guid 2>&1 | Out-Null
    Write-Host "[Power] Active plan: $Plan ($guid)" -ForegroundColor Green
}

Export-ModuleMember -Function Get-WTUActivePowerPlan, Set-WTUPowerPlan
