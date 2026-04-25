<#
.SYNOPSIS  Intel GPU / iGPU power control via registry.
#>

function Set-WTUIntelPowerPreference {
    param([ValidateSet('MaxPerformance','Balanced','PowerSave')][string]$Mode)
    $val = switch ($Mode) { 'MaxPerformance' { 1 } 'Balanced' { 2 } 'PowerSave' { 3 } }
    $base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -Name DriverDesc -EA SilentlyContinue
        if ($p.DriverDesc -match 'Intel') {
            Set-ItemProperty $_.PSPath -Name PowerPolicy -Value $val -Type DWord -Force -EA SilentlyContinue
        }
    }
    Write-Host "[Intel GPU] Power mode set: $Mode" -ForegroundColor Green
}

Export-ModuleMember -Function Set-WTUIntelPowerPreference
