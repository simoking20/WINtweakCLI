function Test-WTUAdmin {
<#
.SYNOPSIS  Verifies current process has Administrator privileges.
.DESCRIPTION  Throws a terminating error if not elevated.
.EXAMPLE  Test-WTUAdmin
#>
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator privileges required. Right-click WinTweakUtility.ps1 -> Run as Administrator."
    }
}
