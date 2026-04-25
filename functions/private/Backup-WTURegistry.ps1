function Backup-WTURegistry {
<#
.SYNOPSIS  Exports a registry path to a .reg file for backup/restore.
.PARAMETER Path       Registry path (HKLM:\... or HKCU:\...).
.PARAMETER OutputFile Optional .reg file destination. Auto-generated if omitted.
.EXAMPLE  Backup-WTURegistry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OutputFile = ""
    )

    $BackupDir = "$env:LOCALAPPDATA\WinTweakUtility\Backups"
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    if (-not $OutputFile) {
        $SafeName   = $Path -replace '[:\\]', '_'
        $OutputFile = Join-Path $BackupDir "${SafeName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    }

    # Convert PowerShell path to reg.exe path
    $RegPath = $Path -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                     -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
                     -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\'

    reg export "$RegPath" "$OutputFile" /y 2>&1 | Out-Null

    if (Test-Path $OutputFile) {
        Write-Verbose "[Backup] Registry exported: $OutputFile"
        return $OutputFile
    } else {
        Write-Warning "[Backup] Failed to export: $Path"
        return $null
    }
}

function Restore-WTURegistry {
<#
.SYNOPSIS  Imports a previously exported .reg backup file.
.PARAMETER BackupFile  Path to the .reg file to import.
.EXAMPLE  Restore-WTURegistry -BackupFile "C:\...\backup.reg"
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupFile)

    if (-not (Test-Path $BackupFile)) {
        throw "Backup file not found: $BackupFile"
    }
    reg import "$BackupFile" 2>&1 | Out-Null
    Write-Verbose "[Restore] Registry imported: $BackupFile"
}
