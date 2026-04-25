<#
.SYNOPSIS  Timer resolution control using NtSetTimerResolution via P/Invoke.
           Add-Type is deferred into a function so it is safe when inlined
           by Compile.ps1 — the C# here-string is only evaluated at call time.
#>

function Initialize-WTUTimerType {
    if (-not ([System.Management.Automation.PSTypeName]'WTUTimerResolution').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WTUTimerResolution {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, ref uint CurrentResolution);
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);
}
"@ -ErrorAction SilentlyContinue
    }
}

function Set-WTUTimerResolution {
<#
.SYNOPSIS  Sets system timer resolution.
.PARAMETER ResolutionMs  Target resolution in milliseconds (e.g. 0.5, 1.0, 15.6).
#>
    param([float]$ResolutionMs)
    Initialize-WTUTimerType
    $desired = [uint]($ResolutionMs * 10000)
    $current = [uint]0
    $null    = [WTUTimerResolution]::NtSetTimerResolution($desired, $true, [ref]$current)
    $actualMs = [Math]::Round($current / 10000.0, 2)
    Write-Host "[Timer] Resolution set to ${actualMs}ms (requested ${ResolutionMs}ms)" -ForegroundColor Green
    return $actualMs
}

function Get-WTUTimerResolution {
<#
.SYNOPSIS  Returns current timer resolution in milliseconds.
#>
    Initialize-WTUTimerType
    [uint]$min=0; [uint]$max=0; [uint]$cur=0
    $null = [WTUTimerResolution]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)
    return [Math]::Round($cur / 10000.0, 2)
}

Export-ModuleMember -Function Set-WTUTimerResolution, Get-WTUTimerResolution, Initialize-WTUTimerType
