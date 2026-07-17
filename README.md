# AR4 Honeycomb Export

MATLAB scripts that generate conformal honeycomb toolpath trajectories and export them as CSV waypoints for the **AR4 6-DOF robot arm**.

## Overview

These scripts bridge the conformal honeycomb trajectory generation (from [Conformal-Trajectory](https://github.com/dianisay/Conformal-Trajectory)) with the AR4 robot. The output is simple comma-separated `X, Y, Z, Orientation` coordinates that can be fed directly into the AR4 controller code.

## Files

| File | Description |
|---|---|
| `ar4_base_test.m` | Simple test patterns (square, hexagon, Z-range) for verifying AR4 communication |
| `export_honeycomb_for_ar4.m` | Full conformal honeycomb trajectory pipeline with AR4 workspace mapping |
| `ar4_extruder_coordinator.m` | Coordinates trajectory with syringe pump extrusion commands (ESP32) |
| `scaffold_curved_void.stl` | Scaffold mesh with void (from Conformal-Trajectory) |

## Quick Start

### Step 1: Test with simple patterns

```matlab
% Run in MATLAB — generates 4 CSV files with basic shapes
ar4_base_test
```

**Output:** `ar4_test_cuadrado.csv`, `ar4_test_hexagono.csv`, `ar4_test_3hexagonos.csv`, `ar4_test_rango_z.csv`

### Step 2: Generate honeycomb trajectory

```matlab
% Run in MATLAB — generates the full conformal honeycomb toolpath
export_honeycomb_for_ar4
```

**Output:** `ar4_honeycomb_paredes.csv`, `ar4_honeycomb_relleno.csv`, `ar4_honeycomb_completo.csv`

### Step 3: Coordinate extruder

```matlab
% Run AFTER step 2 — generates command sequence with extrusion triggers
ar4_extruder_coordinator
```

**Output:** `ar4_commands.csv` — merged trajectory + extrusion commands

With `LIVE_MODE = true`, it also sends HTTP commands directly to the ESP32 syringe pump.

## CSV Format

### Base test files
```
X, Y, Z, Orientation
```

### Honeycomb files
```
X, Y, Z, Orientation, Type
```

- **X, Y, Z** — position in mm
- **Orientation** — 90° (nozzle perpendicular to surface)
- **Type** — `0` = travel move (nozzle up), `1` = deposition move (extruding)

## Configuration

Edit the parameters at the top of each script:

| Parameter | Default | Description |
|---|---|---|
| `AR4_Z_MIN` | 270 mm | Lower Z limit of AR4 workspace |
| `AR4_Z_MAX` | 450 mm | Upper Z limit of AR4 workspace |
| `AR4_Z_SURFACE` | 300 mm | Z height of the scaffold surface |
| `AR4_XY_CENTER` | [0, 300] mm | XY center of the scaffold |
| `CX, CY` | 0, 300 mm | Center of test patterns (base test only) |

## Extruder Integration

The `ar4_extruder_coordinator.m` script works with the [Syringe-Pump-Controller---WIFI](https://github.com/dianisay/Syringe-Pump-Controller---WIFI) (ESP32 + servo MG995).

It reads the honeycomb trajectory CSV, identifies continuous deposition segments, calculates the volume for each segment based on bead diameter, and generates extrusion commands. The output `ar4_commands.csv` has 7 columns:

```
X, Y, Z, Orientation, Type, ExtrudeCmd, VolumeML
```

- `ExtrudeCmd = 0`: no extruder action (just move)
- `ExtrudeCmd = 1`: send `/extrude` to ESP32 with the specified volume
- `VolumeML`: volume in mL for this segment

In `LIVE_MODE = true`, it sends HTTP POST requests directly to the ESP32 in real time.

## Requirements

- MATLAB (tested on R2023b+)
- Optimization Toolbox (for `intlinprog` — TSP cell-order optimization)
- `scaffold_curved_void.stl` in the working directory (or set `USE_STL = false` for manual mode)
- ESP32 syringe pump on the same WiFi network (for live extrusion control)
