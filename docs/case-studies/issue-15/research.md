# Research — Issue #15: Retrowave Animated Background

## 1. Retrowave / Synthwave Visual Aesthetics

### Origin and Characteristics
The retrowave (also spelled "retrowave", also called "synthwave" or "outrun") aesthetic
originates from 1980s science-fiction imagery — specifically the neon-lit, grid-dominated
landscapes of films like *TRON* (1982) and *Blade Runner* (1982), and the cover art of
Atari/Commodore games of that era.

**Canonical visual elements:**

| Element | Description |
|---------|-------------|
| Perspective grid | Wireframe plane of glowing lines converging to a vanishing point on the horizon |
| Retro sun | Large disc, typically gradient from yellow-orange at bottom to hot magenta, with evenly spaced horizontal black bands ("scanlines") |
| Gradient sky | Deep violet/indigo at top blending to hot magenta at the horizon |
| Neon glow | Thin, intensely saturated lines with a soft bloom halo |
| CRT scanlines | Faint horizontal lines mimicking an old cathode-ray tube monitor |
| Dark atmosphere | Near-black ground between grid lines emphasising the glow |

### Colour Palette (Outrun / Synthwave)

| Colour name | Hex | Purpose |
|-------------|-----|---------|
| Laser Lemon | `#FEF65B` | Sun core / bright yellow |
| Heavy Orange | `#FD8A26` | Sun outer rim |
| Hot Pink | `#FF2975` | Grid lines / sun stripes |
| Deep Magenta | `#C600FF` | Grid glow / sky midpoint |
| Cyber Purple | `#4A00B3` | Upper sky |
| Electric Cyan | `#00FFFF` | Alternate palette accent |
| Neon Green | `#20FF0A` | Alternate grid ("plasma") |

Source: The Ultimate Outrun Color Palette Guide — retrowave.com (archived 2024).

---

## 2. Godot 4 Rendering Architecture for Backgrounds

### CanvasLayer ordering
Godot 4 uses `CanvasLayer.layer` (integer, default 0) to sort 2D layers.
Negative values draw *behind* the default layer (where the 3D viewport renders).

**Stack used in this project:**

| Layer | Content |
|-------|---------|
| -1 | Retrowave background (`Background.gd`) |
| 0 (3D viewport) | Candy balls, back panel, lights |
| 0 (CanvasLayer default) | HUD title and line counter |

### Making 3D transparent to the background
Setting `Environment.background_mode = BG_CANVAS` instructs Godot to composite
the 3D viewport *on top of* the CanvasLayer stack rather than clearing with a
solid colour.  This is the correct mechanism for this pattern.

References:
- Godot 4 docs: Environment class — `BG_CANVAS` background mode
- Godot 4 docs: CanvasLayer — layer ordering

---

## 3. Shader Techniques Used

### Perspective Grid (lower half)

The perspective-grid effect is a classic UV transformation:

```glsl
// For a point at vertical position yf (0=bottom of screen, 1=top),
// horizon at yf=horizon_y:
float d = 1.0 / max(horizon_y - yf, epsilon);   // depth ∝ 1 / distance
float pu_x = (xf - 0.5) * d;                    // x converges to centre
float pu_y = d - TIME * scroll_speed;            // y scrolls forward
```

Grid lines are then drawn with `fract()` + `smoothstep()`:

```glsl
float vline_f = fract(pu_x * density + 0.5) - 0.5;
float vline   = smoothstep(thickness, thickness * 0.4, abs(vline_f));
```

Line thickness is scaled by `d` to produce correct perspective foreshortening
(lines look wider closer to the camera).

Sources:
- [Godot Shaders — Perspective Grid Animated](https://godotshaders.com/shader/perspective-grid/)
- [Godot Shaders — Infinite Ground Grid](https://godotshaders.com/shader/infinite-ground-grid/)

### Retro Sun (upper half)

The sun is a radial distance field coloured with two gradients:
1. **Disc alpha**: `smoothstep(radius, radius * 0.5, dist)` — hard-edged disc
2. **Radial colour**: `mix(outer_color, inner_color, ...)` — orange rim → yellow core

Horizontal scanline bands create the signature stripe effect:
```glsl
float band_h = sun_radius / scanline_count;
float scan   = smoothstep(gap_frac, gap_frac * 0.5, mod(yf, band_h));
```
Applied only to the lower half of the disc and mixed multiplicatively.

Source: [Godot Shaders — Retro Sun](https://godotshaders.com/shader/retro-sun/)

### Animation
All animation is driven by the built-in `TIME` uniform (elapsed seconds).
This guarantees frame-rate-independent, infinitely looping animation with
zero GDScript overhead — the GPU handles it entirely.

---

## 4. Existing Components Considered

| Component | What it is | Decision |
|-----------|-----------|----------|
| **Godot Shaders — Perspective Grid** | Canvas-item shader, pure GLSL | Pattern adopted; code written from scratch to integrate sun + grid in one shader |
| **Godot Shaders — Retro Sun** | Canvas-item shader | Pattern adopted; merged into single shader |
| **Godot Asset Library — Synthwave Pack** | No such asset exists at time of writing | — |
| **kenney.nl retrowave assets** | Static PNG art packs | Not suitable for programmatic animation |
| **coi-serviceworker** | COOP/COEP header polyfill | Not relevant to this issue |

---

## 5. Swappable Background Architecture

The issue explicitly requires that *"in the future backgrounds should dynamically
change as the player progresses."*  The chosen design:

```
Background (Node) ──────────────────────────────────────
  _canvas_layer: CanvasLayer (layer = -1)
    _rect: ColorRect (anchors = full screen)
      material: ShaderMaterial → retrowave_background.gdshader
```

Three colour palettes are baked into `Background.gd` as constants:
- `THEME_RETROWAVE` — default neon magenta (levels 0–N)
- `THEME_PLASMA` — electric cyan (mid-game)
- `THEME_NEON` — hot-pink / lime-green (endgame)

Switching theme is a single call: `_background.set_theme(Background.THEME_PLASMA)`.
Only shader uniforms change — no scene nodes are created or destroyed, so the
transition is frame-exact and costs nothing at runtime.

Future extensions could:
- Add a crossfade tween between two material snapshots
- Drive `grid_speed` from the player's line-clear rate for a "speed-up" feel
- Load external `.tres` (ShaderMaterial resource files) for complete shader swaps

---

## 6. Web Export Compatibility

The shader uses `shader_type canvas_item;` — a fully supported shader type in
Godot 4's GL Compatibility renderer (the renderer used for the single-threaded
HTML5 export).  No extensions or non-portable GLSL features are used.

All maths (`fract`, `smoothstep`, `mod`, `mix`, `length`) are GLSL ES 1.0
built-ins available in WebGL 1 / OpenGL ES 2 and above.

The `TIME` uniform is always available in canvas-item shaders and is correctly
populated by Godot's WebAssembly runtime.
