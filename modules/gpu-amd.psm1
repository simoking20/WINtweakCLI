<#
.SYNOPSIS  AMD GPU control (ULPS, Anti-Lag, power tuning via registry).
#>

function Test-WTUAMDAvailable {
    return (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000")
}

function Disable-WTUAMDUlps {
    $base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
        $val = Get-ItemProperty $_.PSPath -Name EnableUlps -EA SilentlyContinue
        if ($null -ne $val) {
            Set-ItemProperty $_.PSPath -Name EnableUlps -Value 0 -Type DWord -Force
        }
    }
    Write-Host "[AMD] ULPS disabled" -ForegroundColor Green
}

function Enable-WTUAMDAntiLag {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\AMD\DirectX" -Name "AntiLag" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "[AMD] Anti-Lag enabled" -ForegroundColor Green
}

Export-ModuleMember -Function Test-WTUAMDAvailable, Disable-WTUAMDUlps, Enable-WTUAMDAntiLag
