#Requires -Version 5.1
<#
.SYNOPSIS
    WinTweak Utility v3.0 - Build Script
.DESCRIPTION
    Merges all modular source files into a single deployable WinTweakUtility.ps1.
    Assembly order: private helpers → public functions → modules → configs → XAML → main.

    KEY SAFETY NOTE:
    - Modules and functions are embedded via StringBuilder.AppendLine(raw content).
      This is NOT a here-string wrapper, so C# here-strings inside modules (@"..."@)
      are preserved as literal file content. No nesting conflict.
    - JSON and XAML are embedded as Base64 strings to avoid ALL quoting issues
      (single-quote escaping, `&amp;`, multiline strings, etc.).

.PARAMETER Run
    Generate and immediately launch the compiled script (as Administrator).
.PARAMETER Validate
    Only validate JSON configs and XAML — no file output produced.
.PARAMETER OutputPath
    Override output file path. Default: WinTweakUtility.ps1 in same directory.
.EXAMPLE
    .\Compile.ps1
    .\Compile.ps1 -Run
    .\Compile.ps1 -Validate
#>
[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$Validate,
    [string]$OutputPath = "$PSScriptRoot\WinTweakUtility.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root       = $PSScriptRoot
$Private    = Join-Path $Root "functions\private"
$Public     = Join-Path $Root "functions\public"
$ModulesDir = Join-Path $Root "modules"
$ConfigDir  = Join-Path $Root "config"
$XamlDir    = Join-Path $Root "xaml"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────
function Write-Step([string]$msg)  { Write-Host "[BUILD] $msg"       -ForegroundColor Cyan   }
function Write-OK  ([string]$msg)  { Write-Host "  [OK]   $msg"      -ForegroundColor Green  }
function Write-Warn([string]$msg)  { Write-Host "  [WARN] $msg"      -ForegroundColor Yellow }
function Write-Fail([string]$msg)  { Write-Host "  [FAIL] $msg"      -ForegroundColor Red    }

function ConvertTo-Base64String([string]$text) {
    # UTF-8 encode → Base64. Safe for ANY content: JSON, XAML, C#, unicode.
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Validate JSON configs
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Validating JSON config files..."
$ConfigFiles  = @('applications.json','tweaks.json','gaming.json','features.json','repairs.json','dns.json','presets.json')
$AllConfigsOK = $true
foreach ($f in $ConfigFiles) {
    $path = Join-Path $ConfigDir $f
    if (Test-Path $path) {
        try {
            $null = Get-Content $path -Raw | ConvertFrom-Json
            Write-OK $f
        } catch {
            Write-Fail "$f - Invalid JSON: $_"
            $AllConfigsOK = $false
        }
    } else {
        Write-Warn "$f not found (will be skipped in output)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Check XAML
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Checking XAML..."
$XamlPath = Join-Path $XamlDir "MainWindow.xaml"
if (Test-Path $XamlPath) {
    try {
        [xml](Get-Content $XamlPath -Raw) | Out-Null
        Write-OK "MainWindow.xaml (XML valid)"
    } catch {
        Write-Fail "MainWindow.xaml - Invalid XML: $_"
        $AllConfigsOK = $false
    }
} else {
    Write-Warn "MainWindow.xaml not found"
}

if ($Validate) {
    if ($AllConfigsOK) {
        Write-Host "`n[BUILD] All validations passed.`n" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n[BUILD] Validation FAILED - see errors above.`n" -ForegroundColor Red
        exit 1
    }
}

# Abort assembly if any config/XAML is broken
if (-not $AllConfigsOK) {
    Write-Host "`n[BUILD] Fix errors above before compiling.`n" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Assemble output using StringBuilder
#
# IMPORTANT: We use StringBuilder.AppendLine(raw-file-content) for ALL PS code.
# This is NOT a here-string wrapper — the raw content is passed as a .NET string.
# C# here-strings (@"..."@) inside modules are just characters in that string;
# they cannot "close" anything in the build script itself.
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Assembling WinTweakUtility.ps1..."
$output = [System.Text.StringBuilder]::new(512KB)

# ── Header comment ──
$null = $output.AppendLine("# =============================================================")
$null = $output.AppendLine("#  WinTweak Utility v3.0  [COMPILED - DO NOT EDIT DIRECTLY]")
$null = $output.AppendLine("#  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $output.AppendLine("#  Source    : github.com/SIMO-Dev/WinTweakUtility")
$null = $output.AppendLine("# =============================================================")
$null = $output.AppendLine("")
$null = $output.AppendLine("#Requires -Version 5.1")
$null = $output.AppendLine("Set-StrictMode -Version Latest")
$null = $output.AppendLine('$ErrorActionPreference = "Stop"')
$null = $output.AppendLine("")

# ── Private helpers ──
Write-Step "Embedding private functions..."
if (Test-Path $Private) {
    Get-ChildItem -Path $Private -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        $null = $output.AppendLine("# --- PRIVATE: $($_.Name) ---")
        $null = $output.AppendLine((Get-Content $_.FullName -Raw))
        $null = $output.AppendLine("")
        Write-OK $_.Name
    }
} else { Write-Warn "functions\private not found" }

# ── Public functions ──
Write-Step "Embedding public functions..."
if (Test-Path $Public) {
    Get-ChildItem -Path $Public -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        $null = $output.AppendLine("# --- PUBLIC: $($_.Name) ---")
        $null = $output.AppendLine((Get-Content $_.FullName -Raw))
        $null = $output.AppendLine("")
        Write-OK $_.Name
    }
} else { Write-Warn "functions\public not found" }

# ── Modules (.psm1) ──
Write-Step "Embedding modules..."
if (Test-Path $ModulesDir) {
    Get-ChildItem -Path $ModulesDir -Filter "*.psm1" | Sort-Object Name | ForEach-Object {
        $null = $output.AppendLine("# --- MODULE: $($_.Name) ---")
        # Strip Export-ModuleMember: only valid inside a real .psm1 module context.
        # In a compiled flat .ps1 all functions are already globally visible.
        $modContent = Get-Content $_.FullName -Raw
        $modContent = $modContent -replace '(?m)^\s*Export-ModuleMember\b.*$', ''
        $null = $output.AppendLine($modContent)
        $null = $output.AppendLine("")
        Write-OK $_.Name
    }
} else { Write-Warn "modules\ not found" }

# ── Embed JSON configs as BASE64 ──────────────────────────────────────────────
# WHY BASE64: Avoids ALL quoting issues — single quotes, ampersands, unicode,
# newlines, and any other special characters in JSON content.
# At runtime: [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(...))
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Embedding JSON configs (Base64)..."
$null = $output.AppendLine("# --- EMBEDDED CONFIGS (Base64-encoded UTF-8) ---")
$null = $output.AppendLine('$sync = @{ configs = @{} }')
foreach ($f in $ConfigFiles) {
    $path = Join-Path $ConfigDir $f
    if (Test-Path $path) {
        $key     = [System.IO.Path]::GetFileNameWithoutExtension($f)
        $b64     = ConvertTo-Base64String (Get-Content $path -Raw)
        # Emit a line that decodes Base64 → JSON at runtime. No quoting issues.
        $null = $output.AppendLine(
            "`$sync.configs['$key'] = ([System.Text.Encoding]::UTF8.GetString(" +
            "[Convert]::FromBase64String('$b64')) | ConvertFrom-Json)"
        )
        Write-OK "$f (Base64, $($b64.Length) chars)"
    }
}
$null = $output.AppendLine("")

# ── Embed XAML as BASE64 ──────────────────────────────────────────────────────
Write-Step "Embedding XAML (Base64)..."
if (Test-Path $XamlPath) {
    $b64Xaml = ConvertTo-Base64String (Get-Content $XamlPath -Raw)
    $null = $output.AppendLine("# --- EMBEDDED XAML (Base64-encoded UTF-8) ---")
    $null = $output.AppendLine(
        "`$inputXML = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64Xaml'))"
    )
    $null = $output.AppendLine("")
    Write-OK "MainWindow.xaml (Base64, $($b64Xaml.Length) chars)"
} else {
    Write-Warn "MainWindow.xaml not found — UI will not load"
}

# ── Main entry point ──
$MainPath = Join-Path $Root "scripts\main.ps1"
if (Test-Path $MainPath) {
    $null = $output.AppendLine("# --- MAIN ENTRY POINT (scripts\main.ps1) ---")
    $null = $output.AppendLine((Get-Content $MainPath -Raw))
} else {
    Write-Warn "scripts\main.ps1 not found — using fallback bootstrap"
    # Fallback: single-quote here-string is safe (no interpolation, no nesting issue)
    $null = $output.AppendLine(@'
# --- FALLBACK BOOTSTRAP ---
Test-WTUAdmin
Initialize-WTUUI -InputXML $inputXML -Config $sync.configs
'@)
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Write output file
# ─────────────────────────────────────────────────────────────────────────────
$output.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
$sizeKB = [Math]::Round((Get-Item $OutputPath).Length / 1KB, 1)
Write-Host "`n[BUILD] Output: $OutputPath  ($sizeKB KB)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Syntax check via PS parser (catches broken here-strings, etc.)
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "Running PowerShell syntax check..."
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $OutputPath, [ref]$null, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    Write-Fail "Syntax errors found in compiled output:"
    $parseErrors | ForEach-Object {
        Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red
    }
    Write-Host "`n[BUILD] FAILED — fix errors above before distributing.`n" -ForegroundColor Red
    exit 1
} else {
    Write-OK "Syntax check passed — 0 errors"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Launch (optional)
# ─────────────────────────────────────────────────────────────────────────────
if ($Run) {
    Write-Step "Launching WinTweakUtility.ps1 as Administrator (STA mode)..."
    Start-Process powershell `
        -ArgumentList "-Sta -ExecutionPolicy Bypass -NoProfile -File `"$OutputPath`"" `
        -Verb RunAs
}

Write-Host "`n[BUILD] Done.`n" -ForegroundColor Cyan
