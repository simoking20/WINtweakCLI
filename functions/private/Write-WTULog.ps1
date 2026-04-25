function Write-WTULog {
<#
.SYNOPSIS  Writes a structured JSONL log entry and human-readable console output.
.PARAMETER Action   The action category (e.g. Tweak, Gaming, Repair).
.PARAMETER Tweak    The specific tweak/entry name.
.PARAMETER Before   State before the action.
.PARAMETER After    State after the action.
.PARAMETER Success  Whether the action succeeded.
.PARAMETER Error    Optional error message.
.EXAMPLE  Write-WTULog -Action Tweak -Tweak WPFTweaksTelemetry -Before "Enabled" -After "Disabled" -Success $true
#>
    [CmdletBinding()]
    param(
        [string]$Action  = "Unknown",
        [string]$Tweak   = "",
        [string]$Before  = "",
        [string]$After   = "",
        [bool]  $Success = $true,
        [string]$Error   = ""
    )

    $LogDir  = "$env:LOCALAPPDATA\WinTweakUtility\Logs"
    $LogFile = Join-Path $LogDir "$(Get-Date -Format 'yyyyMM').jsonl"

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $entry = [PSCustomObject]@{
        timestamp = (Get-Date -Format 'o')
        action    = $Action
        tweak     = $Tweak
        user      = $env:USERNAME
        computer  = $env:COMPUTERNAME
        before    = $Before
        after     = $After
        success   = $Success
        error     = $Error
    }

    # JSONL append
    ($entry | ConvertTo-Json -Compress) | Add-Content -Path $LogFile -Encoding UTF8

    # Console output
    $color = if ($Success) { 'Green' } else { 'Red' }
    $symbol = if ($Success) { '[+]' } else { '[!]' }
    Write-Host "$symbol [$Action] $Tweak" -ForegroundColor $color
    if ($Error) { Write-Host "    Error: $Error" -ForegroundColor Red }
}
