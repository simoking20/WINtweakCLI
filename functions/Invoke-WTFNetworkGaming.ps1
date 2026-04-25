# =============================================================
# Invoke-WTFNetworkGaming.ps1 - WinTweak CLI v3.0
# TCP/IP competitive gaming optimization
# =============================================================

function Invoke-WTFNetworkGaming {
    param(
        [Parameter(Mandatory)][ValidateSet("Optimize","Restore")][string]$Action
    )

    if ($Action -eq "Optimize") {
        Write-Host "[*] Applying TCP/IP gaming optimizations..." -ForegroundColor Cyan

        # Disable Nagle's algorithm (reduces TCP latency)
        $tcpKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        Get-ChildItem $tcpKeyPath -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] Nagle's algorithm disabled (TcpAckFrequency=1, TCPNoDelay=1)" -ForegroundColor Green

        # Network throttling index (disable throttling for games)
        $mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $mmPath -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
        Write-Host "  [+] Network throttling disabled" -ForegroundColor Green

        # DNS Client tuning
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
            -Name "MaxCacheTtl" -Value 86400 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] DNS cache TTL extended" -ForegroundColor Green

        # QoS packet scheduler (allow apps to control QoS)
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" `
            -Name "NonBestEffortLimit" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] QoS reserved bandwidth freed (0%)" -ForegroundColor Green

        # Auto-tuning level
        netsh int tcp set global autotuninglevel=normal 2>$null
        Write-Host "  [+] TCP auto-tuning: normal" -ForegroundColor Green

        # RSS (Receive Side Scaling)
        netsh int tcp set global rss=enabled 2>$null
        Write-Host "  [+] RSS enabled" -ForegroundColor Green

        # Chimney offload
        netsh int tcp set global chimney=disabled 2>$null
        Write-Host "  [+] TCP chimney offload disabled" -ForegroundColor Green

        Write-Host "[+] Network gaming optimizations applied" -ForegroundColor Green
    }
    else {
        Write-Host "[*] Restoring default network settings..." -ForegroundColor Cyan

        $tcpKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        Get-ChildItem $tcpKeyPath -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $_.PSPath -Name "TCPNoDelay"      -Force -ErrorAction SilentlyContinue
        }

        $mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $mmPath -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force

        netsh int tcp set global autotuninglevel=normal 2>$null
        netsh int tcp set global rss=enabled 2>$null
        netsh int tcp set global chimney=disabled 2>$null

        Write-Host "[+] Network settings restored to defaults" -ForegroundColor Green
    }
}
