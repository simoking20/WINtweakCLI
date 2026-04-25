#Requires -Module Pester
<#
.SYNOPSIS  Config validation tests for WinTweak Utility v3.0
#>

$ConfigDir = Join-Path (Split-Path $PSScriptRoot -Parent) "config"

Describe "Config Validation" {

    It "gaming.json exists and is valid JSON" {
        $path = Join-Path $ConfigDir "gaming.json"
        $path | Should -Exist
        { Get-Content $path -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "All gaming.json entries have required fields" {
        $gaming = Get-Content (Join-Path $ConfigDir "gaming.json") -Raw | ConvertFrom-Json
        $gaming.PSObject.Properties | ForEach-Object {
            $_.Value.Content     | Should -Not -BeNullOrEmpty
            $_.Value.Description | Should -Not -BeNullOrEmpty
        }
    }

    It "tweaks.json exists and entries have Content and Description" {
        $path = Join-Path $ConfigDir "tweaks.json"
        $path | Should -Exist
        $tweaks = Get-Content $path -Raw | ConvertFrom-Json
        $tweaks.PSObject.Properties | ForEach-Object {
            $_.Value.Content     | Should -Not -BeNullOrEmpty -Because "$($_.Name) needs Content"
            $_.Value.Description | Should -Not -BeNullOrEmpty -Because "$($_.Name) needs Description"
        }
    }

    It "applications.json entries have winget or choco ID" {
        $path = Join-Path $ConfigDir "applications.json"
        $path | Should -Exist
        $apps = Get-Content $path -Raw | ConvertFrom-Json
        $apps.PSObject.Properties | ForEach-Object {
            $hasWinget = $null -ne $_.Value.winget -and $_.Value.winget -ne ''
            $hasChoco  = $null -ne $_.Value.choco  -and $_.Value.choco  -ne ''
            ($hasWinget -or $hasChoco) | Should -BeTrue -Because "$($_.Name) needs at least one package manager ID"
        }
    }

    It "All 7 gaming modes exist in gaming.json" {
        $gaming = Get-Content (Join-Path $ConfigDir "gaming.json") -Raw | ConvertFrom-Json
        @('WTFModeUltimate','WTFModeCompetitiveStable','WTFModeLatency',
          'WTFModeEsports','WTFModeStable','WTFModeLaptop','WTFModeBattery') | ForEach-Object {
            $gaming.$_ | Should -Not -BeNullOrEmpty -Because "$_ must exist in gaming.json"
        }
    }

    It "dns.json has all required providers" {
        $dns = Get-Content (Join-Path $ConfigDir "dns.json") -Raw | ConvertFrom-Json
        @('DefaultDHCP','Google','Cloudflare','Quad9','AdGuard') | ForEach-Object {
            $dns.$_ | Should -Not -BeNullOrEmpty
        }
    }
}
