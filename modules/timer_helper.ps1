# timer_helper.ps1 - Timer resolution helper script
# Called by timer.bat with -Action parameter
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("SetMaximum","SetEfficient","SetDefault","QueryCurrent")]
    [string]$Action
)

$typeDef = @"
using System;
using System.Runtime.InteropServices;
public class NtTimer {
    [DllImport("ntdll.dll")]
    public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out uint MinResolution, out uint MaxResolution, out uint CurrentResolution);
}
"@

try {
    Add-Type -TypeDefinition $typeDef -ErrorAction Stop
} catch {
    # Type may already be loaded in this session - that's fine
}

switch ($Action) {
    "SetMaximum" {
        $cur = [uint32]0
        $ret = [NtTimer]::NtSetTimerResolution(5000, $true, [ref]$cur)
        if ($ret -eq 0) {
            Write-Host ("  [OK] Timer set to {0:N4} ms  (5000 units = 0.5ms target)" -f ($cur / 10000.0))
        } else {
            Write-Host "  [WARN] NtSetTimerResolution returned: $ret"
        }
    }
    "SetEfficient" {
        $cur = [uint32]0
        $ret = [NtTimer]::NtSetTimerResolution(10000, $true, [ref]$cur)
        if ($ret -eq 0) {
            Write-Host ("  [OK] Timer set to {0:N4} ms  (1.0ms efficient mode)" -f ($cur / 10000.0))
        } else {
            Write-Host "  [WARN] NtSetTimerResolution returned: $ret"
        }
    }
    "SetDefault" {
        $cur = [uint32]0
        $ret = [NtTimer]::NtSetTimerResolution(156001, $false, [ref]$cur)
        Write-Host "  [OK] Timer reset to Windows default (15.6ms)"
    }
    "QueryCurrent" {
        $mn = [uint32]0; $mx = [uint32]0; $cur = [uint32]0
        [NtTimer]::NtQueryTimerResolution([ref]$mn, [ref]$mx, [ref]$cur) | Out-Null
        $curMs  = "{0:N4}" -f ($cur / 10000.0)
        $minMs  = "{0:N4}" -f ($mn  / 10000.0)
        $maxMs  = "{0:N4}" -f ($mx  / 10000.0)
        Write-Host "  Current: $curMs ms  |  Min achievable: $minMs ms  |  Max (default): $maxMs ms"
    }
}
