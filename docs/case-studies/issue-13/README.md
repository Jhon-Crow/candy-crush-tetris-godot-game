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

## Renderer constraints

This project uses the **GL Compatibility** renderer (set in `project.godot` and
`export_presets.cfg`). This renderer is required for single-threaded Web export
on GitHub Pages. As a result, several advanced material features are unavailable
or cause performance issues:

| Feature | Status | Reason |
|---|---|---|
| `refraction_enabled` / `refraction_scale` | ❌ Unavailable | Forward+ only |
| `clearcoat_enabled` / `clearcoat` / `clearcoat_roughness` | ❌ Unavailable | Forward+ only |
| `TRANSPARENCY_ALPHA` | ⚠ Avoided | Triggers expensive per-step transparent-object sorting even in headless mode; with up to 128 settled pieces the 4000-step CI test grew from ~17 s to 2+ minutes |

The crystal look is achieved using only Compatibility-friendly, opaque-material
properties: `metallic`, `roughness`, `metallic_specular`, `rim`, `rim_tint`,
and `emission`.

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
| `metallic_specular` | 0.5 (default) | 1.0 |
| `roughness` | 0.22 | 0.08 |

The reduced rim + tinted `rim_tint` replaces the harsh white halo with a
subtle facet-edge highlight that blends with the crystal colour. The very
low emission provides a hint of internal glow without dominating.

### 3. Crystal appearance (Game.gd)

- **Geometry**: replaced `SphereMesh` with `CylinderMesh` (6 radial segments,
  low-poly hexagonal prism) — gives clearly faceted crystal faces that catch
  light like a cut gemstone.
- **Surface**: `metallic = 0.10`, `roughness = 0.08`, `metallic_specular = 1.0` —
  very smooth, sharp-specular surface that produces bright highlights on the flat
  hexagonal facets. This achieves the glass/crystal impression without requiring
  actual transparency.
- **Colours updated** to jewel-tone palette (ruby, amber, citrine, emerald,
  sapphire, amethyst, rose quartz) that read as gemstones against the dark board.
- All cells in one piece share a colour so the tetromino reads as one crystal.
- Adjusted lighting (slightly reduced ambient energy, lighter back panel) to
  make the facet highlights more visible.

## Testing

All existing headless logic tests continue to pass — the changes are purely
visual (material parameters, mesh geometry, motion interpolation) and do not
affect game logic (grid state, collision detection, line clearing, auto-player).

The opaque material choice (no `TRANSPARENCY_ALPHA`) is specifically required to
keep the CI test runtime within acceptable bounds (~17 s instead of 2+ minutes).
