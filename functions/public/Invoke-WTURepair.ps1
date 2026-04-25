function Invoke-WTURepair {
<#
.SYNOPSIS  Executes a system repair action from repairs.json.
.PARAMETER RepairName  Key from repairs.json (e.g. WTURepairWindowsUpdate).
.PARAMETER Config      Parsed repairs.json object.
.EXAMPLE  Invoke-WTURepair -RepairName WTURepairSFC -Config $sync.configs.repairs
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $RepairName,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $repair = $Config.$RepairName
    if (-not $repair) { throw "Repair not found: $RepairName" }

    Write-Host "[Repair] $($repair.Content)" -ForegroundColor Cyan
    if ($repair.Warning) { Write-Host "  [WARN] $($repair.Warning)" -ForegroundColor Yellow }

    Invoke-WTUSafeExecution -TweakName $RepairName -ScriptBlock {
        foreach ($cmd in $repair.InvokeScript) { Invoke-Expression $cmd }
    }

    Write-WTULog -Action "Repair" -Tweak $RepairName -After "Completed" -Success $true
}
