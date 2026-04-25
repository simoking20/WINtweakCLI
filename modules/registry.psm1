<#
.SYNOPSIS  Registry CRUD module with backup/restore support.
#>

function Get-WTUReg {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name } catch { return $null }
}

function Set-WTUReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Remove-WTUReg {
    param([string]$Path, [string]$Name)
    Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

function Test-WTURegPath { param([string]$Path); return (Test-Path $Path) }

Export-ModuleMember -Function Get-WTUReg, Set-WTUReg, Remove-WTUReg, Test-WTURegPath
