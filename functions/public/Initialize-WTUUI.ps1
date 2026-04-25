function Find-WTUControl {
<#
.SYNOPSIS  Null-safe wrapper around Window.FindName. Warns if control is missing.
           Defined at script scope so the PS parser doesn't flag nested-function depth.
.PARAMETER Window  The WPF Window object.
.PARAMETER Name    The x:Name of the control to find.
#>
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Name
    )
    $ctrl = $Window.FindName($Name)
    if (-not $ctrl) {
        Write-Warning "[UI] Control not found: '$Name' - check x:Name in XAML"
    }
    return $ctrl
}

function Initialize-WTUUI {
<#
.SYNOPSIS  Loads the WPF MainWindow XAML, wires all events, and shows the UI.
.PARAMETER InputXML  Raw XAML string for the main window.
.PARAMETER Config    Hashtable of parsed JSON configs (applications, tweaks, gaming, features, repairs, dns).
.EXAMPLE  Initialize-WTUUI -InputXML $inputXML -Config $sync.configs
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]    $InputXML,
        [Parameter(Mandatory)][hashtable] $Config
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    # Step 2: Validate XAML string is not empty before attempting to load
    if ([string]::IsNullOrWhiteSpace($InputXML)) {
        throw "XAML string is empty. Rebuild with Compile.ps1 and verify MainWindow.xaml was embedded."
    }
    Write-Verbose "[UI] XAML length: $($InputXML.Length) chars"

    # Step 3: Correct XAML load pattern — XmlReader.Create(StringReader) not [xml] cast
    # [xml] cast loses namespace context; XmlNodeReader drops x:Name in some PS versions
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($InputXML))

    # Step 8: try/catch so XAML parse errors are visible instead of silent crash
    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        $msg = "XAML Load Failed:`n$($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        if ([System.Management.Automation.PSTypeName]'System.Windows.MessageBox' -as [type]) {
            [System.Windows.MessageBox]::Show($msg, "WinTweak Utility - XAML Error") | Out-Null
        }
        Read-Host "Press Enter to exit"
        exit 1
    }

    # ---- Populate Install tab ----
    $installPanel = Find-WTUControl $window 'InstallPanel'
    if ($Config.applications) {
        $grouped = $Config.applications.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Foreground = [System.Windows.Media.Brushes]::CornflowerBlue
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in ($g.Group | Sort-Object { $_.Value.Content })) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $item.Value.Content
                $cb.ToolTip = $item.Value.Description
                $cb.Tag     = $item.Name
                $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                $sp.Children.Add($cb) | Out-Null
            }
            $gb.Content = $sp
            if ($installPanel) { $installPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Tweaks tab ----
    $tweaksPanel = Find-WTUControl $window 'TweaksPanel'
    if ($Config.tweaks) {
        $grouped = $Config.tweaks.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $type = $item.Value.Type
                if ($type -in 'CheckBox','Toggle') {
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.Content = $item.Value.Content
                    $cb.ToolTip = $item.Value.Description
                    $cb.Tag     = $item.Name
                    $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                    $sp.Children.Add($cb) | Out-Null
                } elseif ($type -eq 'Button') {
                    $btn = New-Object System.Windows.Controls.Button
                    $btn.Content = $item.Value.Content
                    $btn.ToolTip = $item.Value.Description
                    $btn.Tag     = $item.Name
                    $btn.Margin  = [System.Windows.Thickness]::new(0,4,0,4)
                    $sp.Children.Add($btn) | Out-Null
                }
            }
            $gb.Content = $sp
            if ($tweaksPanel) { $tweaksPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Gaming modes ----
    $modesPanel = Find-WTUControl $window 'GamingModesPanel'
    $modeColors = @{
        'WTFModeUltimate'          = '#69F0AE'
        'WTFModeCompetitiveStable' = '#4FC3F7'
        'WTFModeLatency'           = '#4FC3F7'
        'WTFModeEsports'           = '#FFB74D'
        'WTFModeStable'            = '#FFEB3B'
        'WTFModeLaptop'            = '#64B5F6'
        'WTFModeBattery'           = '#9E9E9E'
    }
    if ($Config.gaming) {
        $modes = $Config.gaming.PSObject.Properties | Where-Object { $_.Value.category -eq 'Gaming Performance Modes' }
        foreach ($m in $modes) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content    = $m.Value.Content
            $btn.ToolTip    = $m.Value.Description
            $btn.Tag        = $m.Name
            $btn.Margin     = [System.Windows.Thickness]::new(0,3,0,3)
            $btn.HorizontalAlignment = 'Stretch'
            $color = if ($modeColors[$m.Name]) { $modeColors[$m.Name] } else { '#C8C8D8' }
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($color)
            if ($modesPanel) { $modesPanel.Children.Add($btn) | Out-Null }
        }
    }

    # ---- Populate Gaming individual tweaks ----
    $tweaksPanelG = Find-WTUControl $window 'GamingTweaksPanel'
    if ($Config.gaming) {
        $indiv = $Config.gaming.PSObject.Properties | Where-Object { $_.Value.category -eq 'Gaming Individual Tweaks' }
        foreach ($t in $indiv) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $t.Value.Content
            $cb.ToolTip = if ($t.Value.Description) { $t.Value.Description } else { $t.Value.Content }
            $cb.Tag     = $t.Name
            $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
            if ($tweaksPanelG) { $tweaksPanelG.Children.Add($cb) | Out-Null }
        }
    }

    # ---- Populate Features tab ----
    $featPanel = Find-WTUControl $window 'FeaturesPanel'
    if ($Config.features) {
        $grouped = $Config.features.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $item.Value.Content
                $cb.ToolTip = $item.Value.Description
                $cb.Tag     = $item.Name
                $cb.Margin  = [System.Windows.Thickness]::new(0,2,0,2)
                $sp.Children.Add($cb) | Out-Null
            }
            $gb.Content = $sp
            if ($featPanel) { $featPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate Repair tab ----
    $repairPanel = Find-WTUControl $window 'RepairPanel'
    if ($Config.repairs) {
        $grouped = $Config.repairs.PSObject.Properties | Group-Object { $_.Value.Category }
        foreach ($g in ($grouped | Sort-Object Name)) {
            $gb = New-Object System.Windows.Controls.GroupBox
            $gb.Header = $g.Name
            $gb.Margin = [System.Windows.Thickness]::new(0,6,0,0)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = [System.Windows.Thickness]::new(0,4,0,0)
            foreach ($item in $g.Group) {
                $btn = New-Object System.Windows.Controls.Button
                $btn.Content    = $item.Value.Content
                $btn.ToolTip    = $item.Value.Description
                $btn.Tag        = $item.Name
                $btn.Margin     = [System.Windows.Thickness]::new(0,4,0,4)
                $btn.HorizontalAlignment = 'Stretch'
                $sp.Children.Add($btn) | Out-Null
            }
            $gb.Content = $sp
            if ($repairPanel) { $repairPanel.Children.Add($gb) | Out-Null }
        }
    }

    # ---- Populate DNS tab ----
    $dnsPanel = Find-WTUControl $window 'DNSPanel'
    if ($Config.dns) {
        foreach ($d in $Config.dns.PSObject.Properties) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $d.Value.Content
            $btn.ToolTip = $d.Value.Description
            $btn.Tag     = $d.Name
            $btn.Margin  = [System.Windows.Thickness]::new(0,0,8,8)
            if ($dnsPanel) { $dnsPanel.Children.Add($btn) | Out-Null }
        }
    }

    # ---- GPU Slider live update (Step 4: null-guard before wiring) ----
    $gpuClockSlider = Find-WTUControl $window 'GPUClockSlider'
    $gpuClockValue  = Find-WTUControl $window 'GPUClockValue'
    $gpuPowerSlider = Find-WTUControl $window 'GPUPowerSlider'
    $gpuPowerValue  = Find-WTUControl $window 'GPUPowerValue'

    if ($gpuClockSlider -and $gpuClockValue) {
        $gpuClockSlider.Add_ValueChanged({ $gpuClockValue.Text = [int]$gpuClockSlider.Value })
    }
    if ($gpuPowerSlider -and $gpuPowerValue) {
        $gpuPowerSlider.Add_ValueChanged({ $gpuPowerValue.Text = "$([int]$gpuPowerSlider.Value)%" })
    }

    # ---- Show window (Step 3: .ShowDialog() not .Show()) ----
    $window.ShowDialog() | Out-Null
}
