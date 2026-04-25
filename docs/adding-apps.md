# Adding a New Application

## Steps

1. Open `config/applications.json`
2. Add a new entry:

```json
"WPFInstallMyApp": {
  "Content":     "My Application",
  "Description": "What this app does.",
  "Category":    "Utilities",
  "Panel":       "Install",
  "Type":        "CheckBox",
  "winget":      "Publisher.AppName",
  "choco":       "app-name",
  "Link":        "https://app-website.com"
}
```

3. Re-run `.\Compile.ps1` — app appears automatically in the Install tab.

## Finding WinGet IDs

```powershell
winget search "app name"
```

## Finding Chocolatey IDs

Visit https://community.chocolatey.org/packages or:
```powershell
choco search "app name"
```

## Categories

Apps are grouped by `Category`. Available categories:
- `Browsers`
- `Development`
- `Gaming`
- `Media`
- `Utilities`

Add any new category string — it will auto-group in the UI.
