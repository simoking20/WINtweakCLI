#Requires -Module Pester
<#
.SYNOPSIS  Safety system tests: checkpoint, rollback, and admin checks.
#>

# Evaluate elevation at discovery time (needed for -Skip)
$script:isAdmin = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Describe "Safety System" {

    BeforeAll {
        $projectRoot  = Split-Path $PSScriptRoot -Parent
        $functionsDir = Join-Path $projectRoot "functions"
        $script:PrivateDir = Join-Path $functionsDir "private"
        $script:PublicDir  = Join-Path $functionsDir "public"

        . (Join-Path $script:PrivateDir "Write-WTULog.ps1")
        . (Join-Path $script:PrivateDir "Backup-WTURegistry.ps1")   # also defines Restore-WTURegistry
        . (Join-Path $script:PublicDir  "Invoke-WTURollback.ps1")
    }

    It "Test-WTUAdmin throws when not elevated" -Skip:$script:isAdmin {
        . (Join-Path $script:PrivateDir "Test-WTUAdmin.ps1")
        { Test-WTUAdmin } | Should -Throw "*Administrator*"
    }

    It "Invoke-WTURollback List does not throw when no checkpoints" {
        { Invoke-WTURollback -Action List } | Should -Not -Throw
    }

    It "Checkpoint Create produces a directory and meta.json" {
        Invoke-WTURollback -Action Create -Name "PesterTest"

        $dir    = "$env:LOCALAPPDATA\WinTweakUtility\Checkpoints"
        $latest = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1

        $latest                                  | Should -Not -BeNullOrEmpty
        (Join-Path $latest.FullName "meta.json") | Should -Exist

        # Cleanup
        Remove-Item $latest.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
