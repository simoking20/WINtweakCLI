$dir = "d:\Developeing side\WIN_twake_cli\WinTweakCLI\modules"
$files = Get-ChildItem "$dir\*.bat"
foreach ($f in $files) {
    $c = Get-Content $f.FullName -Raw
    if ($c -match 'call "%~f0"') {
        Write-Host "HAS: $($f.Name)"
    }
}
