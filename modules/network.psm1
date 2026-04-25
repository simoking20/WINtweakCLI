<#
.SYNOPSIS  TCP/IP network optimization module for gaming.
#>

function Optimize-WTUNetworkGaming {
    # Nagle's algorithm
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' `
        -Name TcpAckFrequency -Value 1 -Type DWord -Force -EA SilentlyContinue
    # Network throttling index (gaming: 0xFFFFFFFF = disabled)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
        -Name NetworkThrottlingIndex -Value 0xFFFFFFFF -Type DWord -Force -EA SilentlyContinue
    # Game scheduling priority
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
        -Name 'GPU Priority' -Value 8 -Type DWord -Force -EA SilentlyContinue
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
        -Name 'Priority' -Value 6 -Type DWord -Force -EA SilentlyContinue
    # Disable auto-tuning (can help on some configs)
    netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    netsh int tcp set global chimney=disabled 2>&1 | Out-Null
    netsh int tcp set global rss=enabled 2>&1 | Out-Null
    Write-Host "[Network] Gaming TCP optimization applied" -ForegroundColor Green
}

function Restore-WTUNetworkDefaults {
    netsh int tcp set global autotuninglevel=normal  2>&1 | Out-Null
    netsh int tcp set global chimney=enabled          2>&1 | Out-Null
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
        -Name NetworkThrottlingIndex -Force -EA SilentlyContinue
    Write-Host "[Network] Defaults restored" -ForegroundColor Green
}

Export-ModuleMember -Function Optimize-WTUNetworkGaming, Restore-WTUNetworkDefaults
