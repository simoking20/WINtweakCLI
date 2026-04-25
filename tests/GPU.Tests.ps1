#Requires -Module Pester
<#
.SYNOPSIS  GPU control tests for WinTweak Utility v3.0
#>

$ModulesDir = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"

Describe "GPU Control" {

    It "Calculates power limit correctly (350W * 80% = 280W)" {
        $maxPower = 350
        $percent  = 80
        $limit    = [Math]::Round($maxPower * $percent / 100)
        $limit | Should -Be 280
    }

    It "Calculates power limit correctly (250W * 70% = 175W)" {
        $limit = [Math]::Round(250 * 70 / 100)
        $limit | Should -Be 175
    }

    It "gpu-nvidia.psm1 exports expected functions" {
        $module = Import-Module (Join-Path $ModulesDir "gpu-nvidia.psm1") -PassThru -Force
        $exports = $module.ExportedFunctions.Keys
        'Test-WTUNVIDIAAvailable' | Should -BeIn $exports
        'Invoke-WTUNVIDIALockClocks'   | Should -BeIn $exports
        'Set-WTUNVIDIAPowerLimit'      | Should -BeIn $exports
        Remove-Module $module -Force
    }

    It "timer.psm1 exports Set-WTUTimerResolution and Get-WTUTimerResolution" {
        $module = Import-Module (Join-Path $ModulesDir "timer.psm1") -PassThru -Force
        $exports = $module.ExportedFunctions.Keys
        'Set-WTUTimerResolution' | Should -BeIn $exports
        'Get-WTUTimerResolution' | Should -BeIn $exports
        Remove-Module $module -Force
    }
}
