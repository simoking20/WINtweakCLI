#Requires -Module Pester
<#
.SYNOPSIS  Registry safety tests for WinTweak Utility v3.0
#>

$FunctionsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "functions"
$PrivateDir   = Join-Path $FunctionsDir "private"

BeforeAll {
    . (Join-Path $PrivateDir "Get-WTUOriginalValue.ps1")
    . (Join-Path $PrivateDir "Backup-WTURegistry.ps1")
    . (Join-Path $PrivateDir "Write-WTULog.ps1")
}

Describe "Registry Safety" {

    It "Never targets critical SafeBoot registry path" {
        $forbidden = @(
            "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot",
            "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa",
            "HKLM:\SAM"
        )
        $ConfigDir = Join-Path (Split-Path $PSScriptRoot -Parent) "config"
        $gaming = Get-Content (Join-Path $ConfigDir "gaming.json") -Raw | ConvertFrom-Json
        foreach ($entry in $gaming.PSObject.Properties) {
            foreach ($reg in $entry.Value.Registry) {
                foreach ($f in $forbidden) {
                    $reg.Path | Should -Not -BeLike "$f*" -Because "Protected path must not be modified by $($entry.Name)"
                }
            }
        }
    }

    It "Get-WTUOriginalValue returns null for non-existent key" {
        $result = Get-WTUOriginalValue -Path "HKCU:\DOES_NOT_EXIST_WTU_TEST" -Name "FakeValue"
        $result | Should -BeNullOrEmpty
    }

    It "Set-WTURegistryEntry creates key if missing" {
        $testPath = "HKCU:\SOFTWARE\WTUTest_Temp_$([System.Guid]::NewGuid().ToString('N'))"
        Set-WTURegistryEntry -Path $testPath -Name "TestVal" -Value 42 -Type DWord
        (Get-ItemProperty -Path $testPath -Name TestVal -EA SilentlyContinue).TestVal | Should -Be 42
        Remove-Item $testPath -Force -ErrorAction SilentlyContinue
    }
}
