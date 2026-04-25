function Get-WTUOriginalValue {
<#
.SYNOPSIS  Reads the current registry value and stores it as the 'OriginalValue' for undo.
.PARAMETER Path  Registry path (HKLM:\ or HKCU:\).
.PARAMETER Name  Registry value name.
.OUTPUTS   The current value, or $null if not found.
.EXAMPLE   $orig = Get-WTUOriginalValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        if (Test-Path $Path) {
            $val = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            return $val.$Name
        }
    }
    catch {
        Write-Verbose "[GetOriginal] Not found: $Path\$Name"
    }
    return $null
}

function Set-WTURegistryEntry {
<#
.SYNOPSIS  Sets a registry value, creating the key path if it doesn't exist.
.PARAMETER Path   Registry path.
.PARAMETER Name   Value name.
.PARAMETER Value  Value to set.
.PARAMETER Type   Registry type (DWord, String, QWord, Binary, ExpandString).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]        $Value,
        [string]$Type = "DWord"
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Verbose "[Registry] Set $Path\$Name = $Value ($Type)"
}
