function Invoke-WTURollback {
<#
.SYNOPSIS  Create, list, restore, delete, or compare system checkpoints.
.PARAMETER Action      Create | List | Restore | Delete | Compare.
.PARAMETER Name        Checkpoint name (for Create).
.PARAMETER Index       Checkpoint index number (for Restore/Delete).
.PARAMETER CompareA    First checkpoint index (for Compare).
.PARAMETER CompareB    Second checkpoint index (for Compare).
.PARAMETER Interactive Prompt user to select checkpoint interactively.
.EXAMPLE  Invoke-WTURollback -Action Create -Name "Before_Gaming"
.EXAMPLE  Invoke-WTURollback -Action Restore -Interactive
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Create','List','Restore','Delete','Compare')][string]$Action,
        [string]$Name      = "Checkpoint",
        [int]   $Index     = 0,
        [int]   $CompareA  = 0,
        [int]   $CompareB  = 1,
        [switch]$Interactive
    )

    $CheckpointDir = "$env:LOCALAPPDATA\WinTweakUtility\Checkpoints"
    $IndexFile     = Join-Path $CheckpointDir "index.txt"
    if (-not (Test-Path $CheckpointDir)) { New-Item -ItemType Directory -Path $CheckpointDir -Force | Out-Null }
    if (-not (Test-Path $IndexFile))     { New-Item -ItemType File -Path $IndexFile -Force | Out-Null }

    switch ($Action) {

        'Create' {
            $ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
            $slug = "checkpoint_${ts}"
            $dir  = Join-Path $CheckpointDir $slug
            New-Item -ItemType Directory -Path $dir | Out-Null

            # Save registry key snapshots
            $keys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
                'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers',
                'HKCU:\System\GameConfigStore',
                'HKCU:\Control Panel\Mouse'
            )
            foreach ($k in $keys) {
                $safe = ($k -replace '[:\\]','_')
                Backup-WTURegistry -Path $k -OutputFile (Join-Path $dir "${safe}.reg")
            }

            # Save power plan
            powercfg /getactivescheme 2>&1 | Out-File (Join-Path $dir "powerplan.txt")

            # Save GPU state
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                nvidia-smi --query-gpu=name,clocks.gr,clocks.mem,power.limit --format=csv 2>&1 | Out-File (Join-Path $dir "gpu_state.txt")
            }

            # Save metadata
            @{ name=$Name; timestamp=$ts; user=$env:USERNAME } | ConvertTo-Json | Set-Content (Join-Path $dir "meta.json")
            Add-Content $IndexFile "${slug}|${Name}|${ts}"
            Write-Host "[Checkpoint] Created: $slug ($Name)" -ForegroundColor Green
            Write-WTULog -Action "Checkpoint" -Tweak "Create" -After $slug -Success $true
        }

        'List' {
            $entries = Get-Content $IndexFile -ErrorAction SilentlyContinue
            if (-not $entries) { Write-Host "  No checkpoints found." -ForegroundColor Yellow; return }
            Write-Host "`n  Checkpoints:" -ForegroundColor Cyan
            $i = 1
            foreach ($e in $entries) {
                $parts = $e -split '\|'
                Write-Host "  [$i] $($parts[0]) - $($parts[1]) ($($parts[2]))"
                $i++
            }
            Write-Host ""
        }

        'Restore' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if (-not $entries) { Write-Host "  No checkpoints to restore." -ForegroundColor Yellow; return }

            if ($Interactive) {
                Invoke-WTURollback -Action List
                $sel = Read-Host "  Select checkpoint number"
                $Index = [int]$sel
            }

            if ($Index -lt 1 -or $Index -gt $entries.Count) { Write-Warning "Invalid index: $Index"; return }
            $slug = ($entries[$Index - 1] -split '\|')[0]
            $dir  = Join-Path $CheckpointDir $slug

            Write-Host "  [Restore] Restoring from: $slug..." -ForegroundColor Yellow
            Get-ChildItem $dir -Filter "*.reg" | ForEach-Object { Restore-WTURegistry -BackupFile $_.FullName }
            $pp = Get-Content (Join-Path $dir "powerplan.txt") -ErrorAction SilentlyContinue
            if ($pp -match 'GUID: ([0-9a-f-]+)') { powercfg -setactive $Matches[1] 2>&1 | Out-Null }
            Write-Host "  [+] Restore complete." -ForegroundColor Green
            Write-WTULog -Action "Checkpoint" -Tweak "Restore" -After $slug -Success $true
        }

        'Delete' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if ($Interactive) {
                Invoke-WTURollback -Action List
                $sel   = Read-Host "  Select checkpoint number to delete"
                $Index = [int]$sel
            }
            if ($Index -lt 1 -or $Index -gt $entries.Count) { Write-Warning "Invalid index"; return }
            $slug = ($entries[$Index - 1] -split '\|')[0]
            $dir  = Join-Path $CheckpointDir $slug
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            $newEntries = $entries | Where-Object { $_ -notmatch "^$slug\|" }
            $newEntries | Set-Content $IndexFile
            Write-Host "  [Deleted] $slug" -ForegroundColor Green
        }

        'Compare' {
            $entries = @(Get-Content $IndexFile -ErrorAction SilentlyContinue)
            if ($entries.Count -lt 2) { Write-Host "  Need at least 2 checkpoints to compare." -ForegroundColor Yellow; return }
            $aSlug = ($entries[$CompareA - 1] -split '\|')[0]
            $bSlug = ($entries[$CompareB - 1] -split '\|')[0]
            Write-Host "`n  Comparing [$CompareA] $aSlug vs [$CompareB] $bSlug" -ForegroundColor Cyan
            $aDir = Join-Path $CheckpointDir $aSlug
            $bDir = Join-Path $CheckpointDir $bSlug
            $aMeta = Get-Content (Join-Path $aDir "meta.json") | ConvertFrom-Json
            $bMeta = Get-Content (Join-Path $bDir "meta.json") | ConvertFrom-Json
            Write-Host "  A: $($aMeta.name) created $($aMeta.timestamp)"
            Write-Host "  B: $($bMeta.name) created $($bMeta.timestamp)"
            # Power plan comparison
            $aP = Get-Content (Join-Path $aDir "powerplan.txt") -EA SilentlyContinue
            $bP = Get-Content (Join-Path $bDir "powerplan.txt") -EA SilentlyContinue
            if ($aP -ne $bP) { Write-Host "  PowerPlan changed between checkpoints." -ForegroundColor Yellow }
            Write-Host ""
        }
    }
}
