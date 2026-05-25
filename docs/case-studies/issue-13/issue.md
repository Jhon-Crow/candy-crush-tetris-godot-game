# Issue #13 — fix фигуры (Fix figures)

Original issue filed by **Jhon-Crow** at
<https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/13>

## Problem statement (translated from Russian)

1. **Jerky falling motion** — figures currently fall in jumps/jolts; they should
   fall smoothly but slowly.
2. **Overly bright shadows and highlights** — rim lighting and emission are too
   intense, need to be toned down.
3. **Crystal-like semi-transparent figures** — figures should look like
   translucent crystals with complex faceted shapes through which light refracts.

## Root cause analysis

### 1. Jerky falling

The `FALL_INTERVAL` is 0.30 s and the `_process()` glide code moves pieces toward
their logical grid position at `CELL / FALL_INTERVAL * 1.6` units/s. In theory
this should be smooth.

The problem is the **relationship between the timer step and the glide speed**.
Each tick the logical position jumps 1 cell (= 1.0 world unit), so the glide
target jumps by 1.0 instantly. The glide speed is 5.33 units/s, which means in
0.30 s the piece travels ~1.6 cells. So the ball *can* catch up, but it may
overshoot if the interval fires again before it arrives, or the visual interpolation
has a sudden jerk at the end of each period.

The deeper issue: `move_toward` is linear and may snap the last few pixels in a
single frame, and the speed constant was chosen empirically without ensuring
smooth exponential decay. The fix is to use **exponential smoothing
(lerp with speed)** instead of `move_toward`, which gives organic, never-snapping
motion, and to slow down the logical fall rate so there is plenty of time for the
glide to look smooth.

### 2. Bright shadows / highlights

Current material settings:
- `rim = 0.5` — rim lighting is quite strong
- `emission_energy_multiplier = 0.22` — self-emission adds a glow
- `roughness = 0.22` — low roughness = very shiny specular highlights

These combine to create very bright, candy-like blobs. The issue asks for
*subtler* shadows/highlights (not darker, just less harsh).

### 3. Crystal appearance

The current balls use `SphereMesh` (smooth) with an opaque material. A crystal
look requires:
- **Semi-transparency** (`transparency = ALPHA`, reduced `alpha`)
- **Refraction** (`refraction_enabled = true` in StandardMaterial3D)
- **Faceted/gem geometry** — an `IcosphereMesh` or `PrismMesh`/`BoxMesh` with a
  faceted normal map gives the appearance of crystal faces
- **Clearcoat layer** for a polished-glass outer surface
- **Higher metallic** (glass refracts, metals reflect — a mix gives gems)
- **Normal map** baked from a gem mesh or procedural noise to fake facets on
  a simpler geometry
