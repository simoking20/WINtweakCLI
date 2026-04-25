# fix_interactive_menus.ps1
# Replaces "if "%_opt%"=="N" call "%~f0" ACTION" 
# with     "if "%_opt%"=="N" ( call "%~f0" ACTION & goto INTERACTIVE_MENU )"
# in all bat files that still have the old pattern

$dir = "d:\Developeing side\WIN_twake_cli\WinTweakCLI\modules"
$targets = @("amd.bat","gpu_memory.bat","input.bat","memory.bat","network.bat","process.bat","registry.bat","services.bat","thermal.bat","backup.bat")

foreach ($fname in $targets) {
    $path = Join-Path $dir $fname
    if (-not (Test-Path $path)) { Write-Host "SKIP (not found): $fname"; continue }
    
    $content = Get-Content $path -Raw
    
    # Pattern: if "%_opt%"=="X" call "%~f0" ACTION
    # Replace with: if "%_opt%"=="X" ( call "%~f0" ACTION & goto INTERACTIVE_MENU )
    $newContent = $content -replace '(if "%_opt%"=="[^"]+") call ("%~f0") ([A-Z_]+)', '$1 ( call $2 $3 & goto INTERACTIVE_MENU )'
    
    if ($newContent -ne $content) {
        Set-Content -Path $path -Value $newContent -NoNewline -Encoding ASCII
        Write-Host "FIXED: $fname"
    } else {
        Write-Host "NO CHANGE: $fname"
    }
}
