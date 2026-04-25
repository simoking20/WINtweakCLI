# WinTweak Utility v3.0

WinTweak Utility v3.0 is a modular, JSON-driven Windows system optimizer. It provides a professional, maintainable WPF-based graphical interface for system tweaking, gaming performance optimization, hardware control, and system repairs.

## Quick Start (For Regular Users)

If you simply want to run the optimizer without touching any code, follow these steps:

### Using the New Graphical Interface 
The new modern interface is much easier to use and replaces the old text menus.
1. Open the `WinTweakCLI` folder.
2. Right-click on the `WinTweakUtility.ps1` file and select **Run with PowerShell**.
3. Click "Yes" if Windows prompts for Administrator permissions.
4. The graphical application will open, and you can simply click to apply your tweaks!

### Using the Old Command-Line Interface (Legacy)
If you prefer the classic text-based console version:
1. Open the main project folder.
2. Right-click the `wtweak.bat` file and select **Run as administrator**.
3. The old text menu will appear in your console.

---

## Developer Documentation

## Project Structure

The project is built on a modular architecture that separates data, UI, and logic:

*   **`config/`**: JSON configuration files. This is the "source of truth" for the application. Editing these files automatically updates the UI without changing any code.
    *   `applications.json`: Apps to install/uninstall via WinGet or Chocolatey.
    *   `tweaks.json`: General system and privacy tweaks.
    *   `gaming.json`: Gaming performance modes and individual gaming tweaks.
    *   `features.json`: Windows optional features to enable/disable.
    *   `repairs.json`: System repair scripts (SFC, DISM, Network Reset, etc.).
    *   `dns.json`: DNS provider configurations.
    *   `presets.json`: One-click combinations of tweaks.
*   **`xaml/MainWindow.xaml`**: The WPF user interface definition.
*   **`functions/`**: PowerShell scripts containing the core logic.
    *   `private/`: Internal helper functions (logging, admin checks, safe execution, registry backup).
    *   `public/`: Public API functions invoked by the UI (`Invoke-WTU*`).
*   **`modules/`**: PowerShell modules (`.psm1`) handling low-level system operations (GPU control, timer resolution, process priority, memory management).
*   **`scripts/main.ps1`**: The main entry point that bootstraps the UI and wires up events.
*   **`Compile.ps1`**: The build script that packages all the above components into a single, deployable `WinTweakUtility.ps1` file.

## How to Build and Run

The project is designed to be developed modularly and deployed as a single script.

### 1. Navigating to the Project Directory
Open PowerShell and navigate to the `WinTweakCLI` directory:
```powershell
cd "d:\Developeing side\WIN_twake_cli\WinTweakCLI"
```
*(Note: Do not run Compile.ps1 from the parent folder. You must be inside the WinTweakCLI folder.)*

### 2. Validating the Configuration
If you have edited any JSON files or the XAML, validate them before building:
```powershell
.\Compile.ps1 -Validate
```

### 3. Building the Executable
To compile all files into a single `WinTweakUtility.ps1` script:
```powershell
.\Compile.ps1
```

### 4. Building and Launching
To compile the utility and immediately launch the WPF interface as Administrator:
```powershell
.\Compile.ps1 -Run
```

## Transition: From CLI to XAML Interface

WinTweak Utility v3.0 marks a complete architectural transition from a legacy text-based batch CLI to a modern WPF (XAML) graphical application. You no longer interact with text menus in the console.

To use the new XAML interface from your CLI:
1. Ensure you have compiled the project using `.\Compile.ps1`.
2. Launch the standalone script from your PowerShell console:
   ```powershell
   .\WinTweakUtility.ps1
   ```
This script acts as the bridge—executed from the CLI, it bootstraps the WPF environment, loads the embedded XAML presentation layer, parses the JSON configurations, and opens the fully functional graphical user interface.

## How to Customize (Developer Guidelines)

*   **Adding new tweaks/apps/modes**: You do **not** need to write PowerShell code to add standard tweaks. Simply open the relevant file in the `config/` folder (e.g., `tweaks.json`), add your new entry following the existing JSON schema, and run `.\Compile.ps1`. The UI will dynamically generate the new options.
*   **Safety & Rollbacks**: All system modifications are routed through `Invoke-WTUSafeExecution`, which automatically captures original registry values. The tool features a robust checkpoint system (`%LOCALAPPDATA%\WinTweakUtility\Checkpoints\`) that saves registry states, power plans, and GPU configurations before applying major gaming modes.
*   **Logging**: All actions are logged in JSON Lines format to `%LOCALAPPDATA%\WinTweakUtility\Logs\`.

## Running Tests
To ensure system safety and configuration integrity, run the Pester test suite:
```powershell
cd "d:\Developeing side\WIN_twake_cli\WinTweakCLI"
Invoke-Pester tests\
```
