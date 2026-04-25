# Adding a New Gaming Mode

## Steps

1. Open `config/gaming.json`
2. Add a new entry under `Gaming Performance Modes` category:

```json
"WTFModeMyMode": {
  "Content":     "My Gaming Mode",
  "Description": "Brief description of what this mode does.",
  "category":    "Gaming Performance Modes",
  "Type":        "Button",
  "Warning":     "Optional: warn the user about risks.",
  "RestartRequired": false,
  "Registry": [
    { "Path": "...", "Name": "...", "Value": "...", "Type": "DWord", "OriginalValue": "..." }
  ],
  "InvokeScript": [
    "Invoke-WTFTimerControl -Resolution 0.5",
    "Invoke-WTFGPUControl -Vendor NVIDIA -LockClocks 1800 -PowerLimitPercent 80"
  ],
  "UndoScript": [
    "Invoke-WTFTimerControl -Resolution 15.6",
    "Invoke-WTFGPUControl -Vendor NVIDIA -UnlockClocks -PowerLimitPercent 100"
  ],
  "EstimatedImpact": {
    "input_lag_ms": "~Xms",
    "thermal_sustainability": "XX-XXC",
    "sustained_1pct_lows": "XX% of avg",
    "best_for": "..."
  }
}
```

3. Re-run `.\Compile.ps1` — mode appears automatically in the Gaming tab.

## Available Helper Functions

| Function | Purpose |
|----------|---------|
| `Invoke-WTFTimerControl -Resolution X` | Set timer to 0.5, 1.0, or 15.6ms |
| `Invoke-WTFGPUControl -LockClocks X` | Lock GPU core clock (NVIDIA) |
| `Invoke-WTFGPUControl -PowerLimitPercent X` | Set power limit % |
| `Invoke-WTFNetworkGaming -Action Optimize` | TCP/IP gaming tweaks |
| `Invoke-WTFProcessOptimize -CoreIsolation` | CPU core isolation |
| `Invoke-WTFMemoryOptimize -Action Clean` | Clear standby RAM |

## Mode Comparison (Reference)

| Mode | GPU | Power | Timer | Input Lag | Temps |
|------|-----|-------|-------|-----------|-------|
| Ultimate | Boost | 100% | 0.5ms | ~10ms | 80-85°C |
| **Comp Stable** | **1800 locked** | **80%** | **0.5ms** | **~7ms** | **70-75°C** |
| Latency | Boost | 100% | 0.5ms | ~6ms | 80-85°C |
| Esports | 1800 locked | 85% | 0.5ms | ~6.5ms | 72-77°C |
| Stable | 1500 locked | 70% | 1.0ms | ~12ms | 65-70°C |
| Laptop | Adaptive | Adaptive | 1.0ms | ~12ms | Adaptive |
| Battery | Min | 50% | 15.6ms | ~25ms | Cool |
