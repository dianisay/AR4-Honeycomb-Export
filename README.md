# AR4 Honeycomb Export

MATLAB scripts that generate conformal honeycomb toolpath trajectories and export them as CSV waypoints for the **AR4 6-DOF robot arm**.

## Overview

These scripts bridge the conformal honeycomb trajectory generation (from [Conformal-Trajectory](https://github.com/dianisay/Conformal-Trajectory)) with the AR4 robot. The output is simple comma-separated `X, Y, Z, Orientation` coordinates that can be fed directly into the AR4 controller code.

## Files

| File | Description |
|---|---|
| `ar4_base_test.m` | Simple test patterns (square, hexagon, Z-range) for verifying AR4 communication |
| `export_honeycomb_for_ar4.m` | Full conformal honeycomb trajectory pipeline with AR4 workspace mapping |
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

## Requirements

- MATLAB (tested on R2023b+)
- Optimization Toolbox (for `intlinprog` — TSP cell-order optimization)
- `scaffold_curved_void.stl` in the working directory (or set `USE_STL = false` for manual mode)
