# =============================================================
# Invoke-WTFMemoryOptimize.ps1 - WinTweak CLI v3.0
# RAM cleanup and standby list management
# =============================================================

function Invoke-WTFMemoryOptimize {
    param(
        [Parameter(Mandatory)][ValidateSet("Clean","Report")][string]$Action
    )

    if ($Action -eq "Report") {
        $os = Get-CimInstance Win32_OperatingSystem
        $used   = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $total  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $usedPc = [math]::Round(($used / $total) * 100, 1)
        Write-Host "[Memory Usage] Used: ${used} / ${total} GB (${usedPc}%)" -ForegroundColor Cyan
        return
    }

    Write-Host "[*] Optimizing RAM and clearing standby list..." -ForegroundColor Cyan

    # Use RAMMap-style EmptyWorkingSet via P/Invoke
    $code = @"
using System;
using System.Runtime.InteropServices;
public class MemHelper {
    [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}
"@
    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue

    # Clear working sets of all accessible processes
    $cleared = 0
    Get-Process | ForEach-Object {
        try {
            [MemHelper]::EmptyWorkingSet($_.Handle) | Out-Null
            $cleared++
        } catch { }
    }
    Write-Host "  [+] Cleared working sets for $cleared processes" -ForegroundColor Green

    # Use NtSetSystemInformation to flush standby list (requires elevation)
    $ntCode = @"
using System;
using System.Runtime.InteropServices;
public class NtMemory {
    [DllImport("ntdll.dll")] public static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
    public static void FlushStandbyList() {
        IntPtr ptr = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(ptr, 4); // MemoryPurgeStandbyList
        NtSetSystemInformation(80, ptr, 4);
        Marshal.FreeHGlobal(ptr);
    }
}
"@
    Add-Type -TypeDefinition $ntCode -ErrorAction SilentlyContinue
    try {
        [NtMemory]::FlushStandbyList()
        Write-Host "  [+] Standby list flushed" -ForegroundColor Green
    } catch {
        Write-Warning "  [!] Could not flush standby list (may need elevated privileges)"
    }

    # Force GC on PowerShell runtime
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Write-Host "  [+] .NET garbage collection triggered" -ForegroundColor Green

    # Report new state
    $os     = Get-CimInstance Win32_OperatingSystem
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    Write-Host "[+] Memory optimization complete. Free RAM: ${freeGB} GB" -ForegroundColor Green
}
