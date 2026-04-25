<#
.SYNOPSIS  RAM cleanup and standby list purge module.
           Add-Type is deferred into a private helper so it is safe when
           inlined by Compile.ps1 — not evaluated until the function runs.
#>

function Initialize-WTUMemoryType {
    if (-not ([System.Management.Automation.PSTypeName]'WTUMemory').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUMemory {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
"@ -ErrorAction SilentlyContinue
    }
}

function Clear-WTUStandbyList {
<#
.SYNOPSIS  Clears the memory standby list. Falls back to working set trim.
.NOTE      Full standby-list purge requires RAMMap or NtSetSystemInformation (admin).
#>
    Initialize-WTUMemoryType

    $procs = Get-Process -ErrorAction SilentlyContinue
    $trimmed = 0
    foreach ($p in $procs) {
        try {
            [WTUMemory]::EmptyWorkingSet($p.Handle) | Out-Null
            $trimmed++
        } catch {}
    }
    Write-Host "[Memory] Working sets trimmed across $trimmed processes" -ForegroundColor Green

    $rammap = Get-Command RAMMap.exe -ErrorAction SilentlyContinue
    if ($rammap) {
        Start-Process RAMMap.exe -ArgumentList "-AcceptEula -Et" -Wait -WindowStyle Hidden
        Write-Host "[Memory] RAMMap standby list purged" -ForegroundColor Green
    }
}

function Get-WTUMemoryStats {
    $os     = Get-CimInstance Win32_OperatingSystem
    $freeMB  = [Math]::Round($os.FreePhysicalMemory / 1024)
    $totalMB = [Math]::Round($os.TotalVisibleMemorySize / 1024)
    $usedMB  = $totalMB - $freeMB
    return @{
        UsedMB  = $usedMB
        FreeMB  = $freeMB
        TotalMB = $totalMB
        UsedPct = [Math]::Round($usedMB * 100 / $totalMB)
    }
}

Export-ModuleMember -Function Clear-WTUStandbyList, Get-WTUMemoryStats, Initialize-WTUMemoryType
