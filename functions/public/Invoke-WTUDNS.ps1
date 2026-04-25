function Invoke-WTUDNS {
<#
.SYNOPSIS  Applies a DNS provider configuration to all active network adapters.
.PARAMETER ProviderName  Key from dns.json (e.g. Cloudflare, Google, DefaultDHCP).
.PARAMETER Config        Parsed dns.json object.
.EXAMPLE  Invoke-WTUDNS -ProviderName Cloudflare -Config $sync.configs.dns
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]       $ProviderName,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $provider = $Config.$ProviderName
    if (-not $provider) { throw "DNS provider not found: $ProviderName" }

    Write-Host "[DNS] Setting: $($provider.Content)" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    foreach ($adapter in $adapters) {
        Write-Host "  Adapter: $($adapter.Name)" -ForegroundColor DarkGray
        try {
            if ($provider.IPv4Primary -eq '') {
                # Reset to DHCP
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-Host "  [OK] Reset to DHCP" -ForegroundColor Green
            } else {
                $dns4 = @($provider.IPv4Primary)
                if ($provider.IPv4Secondary) { $dns4 += $provider.IPv4Secondary }
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dns4
                Write-Host "  [OK] IPv4: $($dns4 -join ', ')" -ForegroundColor Green

                if ($provider.IPv6Primary) {
                    $dns6 = @($provider.IPv6Primary)
                    if ($provider.IPv6Secondary) { $dns6 += $provider.IPv6Secondary }
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dns6
                    Write-Host "  [OK] IPv6: $($dns6 -join ', ')" -ForegroundColor Green
                }
            }
        } catch {
            Write-Warning "  Failed on $($adapter.Name): $_"
        }
    }

    # Flush DNS cache
    Clear-DnsClientCache
    Write-Host "[DNS] Cache flushed. Done." -ForegroundColor Green
    Write-WTULog -Action "DNS" -Tweak $ProviderName -After "Applied" -Success $true
}
