function Test-WTUConfig {
<#
.SYNOPSIS  Validates a WinTweak Utility config JSON object against required fields.
.PARAMETER Config     Parsed JSON object (PSCustomObject) from a config file.
.PARAMETER ConfigName Name of the config for error messages.
.EXAMPLE  Test-WTUConfig -Config ($json | ConvertFrom-Json) -ConfigName "gaming.json"
.OUTPUTS  [bool] $true if valid, throws on invalid.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [string]$ConfigName = "config"
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($prop in $Config.PSObject.Properties) {
        $entry = $prop.Value
        $name  = $prop.Name

        if ([string]::IsNullOrWhiteSpace($entry.Content)) {
            $errors.Add("[$name] Missing required field: Content")
        }
        if ([string]::IsNullOrWhiteSpace($entry.Description)) {
            $errors.Add("[$name] Missing required field: Description")
        }
        # Validate Registry entries if present
        if ($entry.Registry) {
            foreach ($reg in $entry.Registry) {
                if (-not $reg.Path) { $errors.Add("[$name] Registry entry missing Path") }
                if (-not $reg.Name) { $errors.Add("[$name] Registry entry missing Name") }
            }
        }
    }

    if ($errors.Count -gt 0) {
        $msg = "Config validation failed for '$ConfigName':`n" + ($errors -join "`n")
        throw $msg
    }

    Write-Verbose "[Validate] $ConfigName OK ($($Config.PSObject.Properties.Count) entries)"
    return $true
}
