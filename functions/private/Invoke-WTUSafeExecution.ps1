function Invoke-WTUSafeExecution {
<#
.SYNOPSIS  Wraps a script block with pre-backup, execution, logging, and rollback on failure.
.PARAMETER ScriptBlock  Code to execute.
.PARAMETER TweakName    Name for logging.
.PARAMETER BackupPath   Optional registry path to back up before executing.
.PARAMETER UndoBlock    Rollback script block if execution fails.
.EXAMPLE
    Invoke-WTUSafeExecution -TweakName "DisableTelemetry" -ScriptBlock {
        Set-ItemProperty 'HKLM:\...' -Name AllowTelemetry -Value 0
    } -UndoBlock {
        Set-ItemProperty 'HKLM:\...' -Name AllowTelemetry -Value 1
    }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$TweakName  = "Unknown",
        [string]$BackupPath = "",
        [scriptblock]$UndoBlock = $null
    )

    $backupFile = $null
    $before = "pre-execution"

    # Optional registry backup
    if ($BackupPath) {
        try { $backupFile = Backup-WTURegistry -Path $BackupPath }
        catch { Write-Warning "[Safe] Backup failed: $_" }
    }

    try {
        & $ScriptBlock
        Write-WTULog -Action "Execute" -Tweak $TweakName -Before $before -After "applied" -Success $true
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-WTULog -Action "Execute" -Tweak $TweakName -Before $before -After "FAILED" -Success $false -Error $errMsg
        Write-Warning "[Safe] $TweakName FAILED: $errMsg"

        # Attempt rollback
        if ($UndoBlock) {
            Write-Host "[Safe] Rolling back $TweakName..." -ForegroundColor Yellow
            try {
                & $UndoBlock
                Write-Host "[Safe] Rollback successful." -ForegroundColor Green
            } catch {
                Write-Warning "[Safe] Rollback also failed: $($_.Exception.Message)"
                if ($backupFile) {
                    Write-Host "[Safe] Restoring registry from backup..." -ForegroundColor Yellow
                    Restore-WTURegistry -BackupFile $backupFile
                }
            }
        }
        throw
    }
}
