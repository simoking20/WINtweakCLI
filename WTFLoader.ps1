# =============================================================
# WTFLoader.ps1 - WinTweak CLI v3.0
# Dot-sources all Invoke-WTF* functions and gaming.json config
# Usage: . "$PSScriptRoot\WTFLoader.ps1"
# =============================================================

$ErrorActionPreference = "Stop"

$functionsDir = Join-Path $PSScriptRoot "functions"
$configDir    = Join-Path $PSScriptRoot "config"

# Auto-load all Invoke-WTF*.ps1 functions
if (Test-Path $functionsDir) {
    Get-ChildItem -Path $functionsDir -Filter "Invoke-WTF*.ps1" | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "[Loaded] $($_.Name)"
        } catch {
            Write-Warning "[LOAD ERROR] $($_.Name): $_"
        }
    }
} else {
    Write-Warning "functions/ directory not found: $functionsDir"
}

# Load gaming.json as a global config object
$gamingJsonPath = Join-Path $configDir "gaming.json"
if (Test-Path $gamingJsonPath) {
    $global:WTFGamingConfig = Get-Content $gamingJsonPath -Raw | ConvertFrom-Json
    Write-Verbose "[Loaded] gaming.json  ($($global:WTFGamingConfig.PSObject.Properties.Count) entries)"
} else {
    Write-Warning "gaming.json not found: $gamingJsonPath"
}

Write-Host "[WinTweak CLI v3.0] Functions loaded. Type 'Get-Command Invoke-WTF*' to list." -ForegroundColor Cyan
