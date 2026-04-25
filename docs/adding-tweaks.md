# Adding a New Tweak

## Steps

1. Open `config/tweaks.json`
2. Add a new entry following the schema:

```json
"WPFTweaksMyNewTweak": {
  "Content":     "My Tweak Display Name",
  "Description": "What this tweak does. Shown as tooltip.",
  "Category":    "Performance",
  "Panel":       "Tweaks",
  "Type":        "CheckBox",
  "RequiresAdmin": true,
  "RestartRequired": false,
  "Registry": [
    {
      "Path":          "HKLM:\\SOFTWARE\\Example",
      "Name":          "MyValue",
      "Value":         "1",
      "Type":          "DWord",
      "OriginalValue": "0"
    }
  ],
  "InvokeScript": ["optional PowerShell command"],
  "UndoScript":   ["PowerShell to revert"],
  "Link": "https://docs link"
}
```

3. Re-run `.\Compile.ps1` to rebuild — **no code changes needed**.

## Supported Types

| Type | UI Element | When to use |
|------|-----------|-------------|
| `CheckBox` | Toggle checkbox | Reversible on/off tweak |
| `Button` | Clickable button | One-time action |
| `Toggle` | Two-state switch | On/off with distinct scripts |
| `ComboBox` | Dropdown | Multiple options |

## Categories

Tweaks are grouped in the UI by the `Category` field. Use existing categories or create new ones:
- `Essential Tweaks`
- `Privacy`  
- `Performance`
- `Advanced Tweaks`
