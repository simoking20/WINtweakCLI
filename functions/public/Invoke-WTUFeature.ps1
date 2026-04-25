function Invoke-WTUFeature {
<#
.SYNOPSIS  Enables or disables a Windows optional feature from features.json.
.PARAMETER FeatureName  Key from features.json (e.g. WPFFeatureWSL).
.PARAMETER Config       Parsed features.json object.
.PARAMETER Disable      If specified, runs DisableScript (UndoScript).
.EXAMPLE  Invoke-WTUFeature -FeatureName WPFFeatureWSL -Config $sync.configs.features
.EXAMPLE  Invoke-WTUFeature -FeatureName WPFFeatureHyperV -Config $sync.configs.features -Disable
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $FeatureName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Disable
    )

    $feat = $Config.$FeatureName
    if (-not $feat) { throw "Feature not found: $FeatureName" }

    $action = if ($Disable) { "Disable" } else { "Enable" }
    Write-Host "[$action] $($feat.Content)" -ForegroundColor Cyan
    if ($feat.Warning) { Write-Host "  [WARN] $($feat.Warning)" -ForegroundColor Yellow }
    if ($feat.RestartRequired) { Write-Host "  [INFO] Restart required." -ForegroundColor Yellow }

    Invoke-WTUSafeExecution -TweakName $FeatureName -ScriptBlock {
        $scripts = if ($Disable) { $feat.UndoScript } else { $feat.InvokeScript }
        foreach ($cmd in $scripts) { Invoke-Expression $cmd }
    }

    Write-WTULog -Action "Feature" -Tweak $FeatureName -After $action -Success $true
}
