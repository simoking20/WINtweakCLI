function Invoke-WTUTweak {
<#
.SYNOPSIS  Applies or undoes a system tweak from tweaks.json.
.PARAMETER TweakName  Key name from tweaks.json (e.g. WPFTweaksTelemetry).
.PARAMETER Config     Parsed tweaks.json object.
.PARAMETER Undo       If specified, runs UndoScript and restores OriginalValues.
.EXAMPLE  Invoke-WTUTweak -TweakName WPFTweaksTelemetry -Config $sync.configs.tweaks
.EXAMPLE  Invoke-WTUTweak -TweakName WPFTweaksTelemetry -Config $sync.configs.tweaks -Undo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $TweakName,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [switch]$Undo
    )

    $entry = $Config.$TweakName
    if (-not $entry) { throw "Tweak not found: $TweakName" }

    $mode = if ($Undo) { "Undo" } else { "Apply" }
    Write-Host "[$mode] $($entry.Content)" -ForegroundColor Cyan

    Invoke-WTUSafeExecution -TweakName $TweakName -ScriptBlock {

        if (-not $Undo) {
            # ---- APPLY ----
            # Registry
            foreach ($reg in $entry.Registry) {
                Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type
            }
            # Services
            foreach ($svc in $entry.Service) {
                try { Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction SilentlyContinue } catch {}
            }
            # InvokeScript
            foreach ($cmd in $entry.InvokeScript) {
                Invoke-Expression $cmd
            }
            # Remove AppX packages
            foreach ($pkg in $entry.Appx) {
                Get-AppxPackage $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            }
        } else {
            # ---- UNDO ----
            # Restore registry OriginalValues
            foreach ($reg in $entry.Registry) {
                if ($null -ne $reg.OriginalValue) {
                    Set-WTURegistryEntry -Path $reg.Path -Name $reg.Name -Value $reg.OriginalValue -Type $reg.Type
                }
            }
            # Restore services
            foreach ($svc in $entry.Service) {
                if ($svc.OriginalType) {
                    try { Set-Service -Name $svc.Name -StartupType $svc.OriginalType -ErrorAction SilentlyContinue } catch {}
                }
            }
            # UndoScript
            foreach ($cmd in $entry.UndoScript) {
                Invoke-Expression $cmd
            }
        }
    }

    Write-WTULog -Action "Tweak" -Tweak $TweakName -After $mode -Success $true
}
