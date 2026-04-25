# =============================================================
# Invoke-WTFTimerControl.ps1 - WinTweak CLI v3.0
# Windows timer resolution: 0.5ms / 1.0ms / 15.6ms (default)
# =============================================================

function Invoke-WTFTimerControl {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(0.5, 1.0, 15.6)]
        [double]$Resolution
    )

    Write-Host "[*] Setting timer resolution to ${Resolution}ms..." -ForegroundColor Cyan

    $signature = @"
    [DllImport("winmm.dll", EntryPoint="timeBeginPeriod")] public static extern uint timeBeginPeriod(uint uPeriod);
    [DllImport("winmm.dll", EntryPoint="timeEndPeriod")]   public static extern uint timeEndPeriod(uint uPeriod);
"@
    $timer = Add-Type -MemberDefinition $signature -Name "WinmmTimer" -Namespace WinTweakCLI -PassThru

    if ($Resolution -eq 15.6) {
        $timer::timeEndPeriod(1) | Out-Null
        Write-Host "  [+] Timer reset to default (15.6ms)" -ForegroundColor Green
    } else {
        # timeBeginPeriod uses 100-nanosecond units (1ms = 10000)
        $period = [uint32]($Resolution * 10000)
        $result = $timer::timeBeginPeriod($period)
        if ($result -eq 0) {
            Write-Host "  [+] Timer resolution set to ${Resolution}ms" -ForegroundColor Green
        } else {
            Write-Warning "Failed to set timer resolution. Error code: $result"
        }
    }
}
