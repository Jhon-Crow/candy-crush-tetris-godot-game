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

## Renderer constraint

This project uses the **GL Compatibility** renderer (set in `project.godot` and
`export_presets.cfg`). This renderer is required for single-threaded Web export
on GitHub Pages. As a result, some advanced material features available in the
Forward+ renderer are **not available**:

- `refraction_enabled` / `refraction_scale` — Forward+ only
- `clearcoat_enabled` / `clearcoat` / `clearcoat_roughness` — Forward+ only

The crystal look is achieved using only Compatibility-supported properties:
`TRANSPARENCY_ALPHA`, `metallic`, `roughness`, `metallic_specular`, `rim`,
`rim_tint`, and `emission`.

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
| `rim` | 0.5 | 0.14 (tinted 0.70 toward albedo) |
| `emission_energy_multiplier` | 0.22 | 0.07 |
| `metallic_specular` | 0.5 (default) | 0.9 |
| `roughness` | 0.22 | 0.10 |

The reduced rim + tinted rim_tint replaces the harsh white halo with a
subtle facet-edge highlight that blends with the crystal colour. The very
low emission provides a hint of internal glow without dominating.

### 3. Crystal appearance (Game.gd)

- **Geometry**: replaced `SphereMesh` with `CylinderMesh` (6 radial segments,
  low-poly hexagonal prism) — gives clearly faceted crystal faces.
- **Transparency**: `transparency = TRANSPARENCY_ALPHA`, `albedo_color.a = 0.62`
- **Surface**: `metallic = 0.08`, `roughness = 0.10`, `metallic_specular = 0.9` —
  smooth glass-like surface.
- **Shadow casting disabled** on crystal pieces to avoid ugly blocky shadows
  from alpha-blended geometry.
- Adjusted lighting (slightly reduced ambient energy, lighter back panel) to
  show transparency better against the background.
- **Colours updated** to jewel-tone palette (ruby, amber, citrine, emerald,
  sapphire, amethyst, rose quartz) that look rich through transparency.
- All cells in one piece share a colour so the tetromino reads as one crystal.

## Testing

All existing headless logic tests continue to pass — the changes are purely
visual (material parameters, mesh geometry, motion interpolation) and do not
affect game logic (grid state, collision detection, line clearing, auto-player).
