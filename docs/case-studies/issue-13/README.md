# Case study — Issue #13: fix фигуры

**Issue:** <https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/13>  
**Branch:** `issue-13-d31d492bea07`  
**PR:** <https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/pull/14>

## Summary of requirements

1. **Smooth falling** — figures fall in jerky jumps; should fall smoothly but slowly.
2. **Subtle shadows/highlights** — rim lighting and emission are too bright/harsh.
3. **Crystal appearance** — figures should look like semi-transparent crystals with
   complex faceted shapes through which light refracts.

## Root cause analysis

See [issue.md](issue.md) for detailed root cause analysis.

## Research

See [research.md](research.md) for prior art, Godot 4 material properties, and
alternative approaches researched.

## Solution implemented

### 1. Smooth falling (Game.gd)

- Slowed `FALL_INTERVAL` from `0.30` s to `0.55` s — gives more real time for
  visual interpolation.
- Replaced `move_toward` linear glide with **exponential smoothing** (`lerp` with
  `1 - exp(-λ·dt)` factor, λ = 12). This gives a natural ease-out that never
  snaps and is frame-rate independent.

### 2. Subtle shadows/highlights (Game.gd `_make_crystal()`)

Material tuning in the new `_make_crystal()` function:

| Parameter | Before | After |
|---|---|---|
| `rim` | 0.5 | 0.12 |
| `rim_tint` | 0.0 | 0.6 |
| `emission_energy_multiplier` | 0.22 | 0.06 |
| `clearcoat` | — | 0.85 |
| `clearcoat_roughness` | — | 0.05 |

Clearcoat provides a crisp, subtle top-layer highlight without the harsh bright
blobs of the old rim+emission combination.

### 3. Crystal appearance (Game.gd)

- **Geometry**: replaced `SphereMesh` with `CylinderMesh` (6 radial segments,
  low-poly hexagonal prism) — gives clearly faceted crystal faces.
- **Transparency**: `transparency = TRANSPARENCY_ALPHA`, `albedo_color.a = 0.62`
- **Refraction**: `refraction_enabled = true`, `refraction_scale = 0.05` —
  subtly warps the background through the crystal.
- **Surface**: `metallic = 0.08`, `roughness = 0.08` — very smooth glass-like
  surface.
- **Shadow casting disabled** on crystal pieces to avoid ugly blocky shadows
  from alpha-blended geometry.
- Adjusted lighting (slightly reduced ambient energy) to prevent washed-out
  transparency.

## Testing

All existing headless logic tests continue to pass — the changes are purely
visual (material, mesh, motion interpolation) and do not affect game logic
(grid state, collision, line clearing, auto-player).
