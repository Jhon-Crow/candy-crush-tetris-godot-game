# Case study — issue #15: "Retrowave animated background"

Deep-dive write-up for
[issue #15](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/15).

1. [What was asked](#1-what-was-asked)
2. [Problem analysis](#2-problem-analysis)
3. [Prior art & existing components](#3-prior-art--existing-components)
4. [Options considered](#4-options-considered)
5. [Chosen approach](#5-chosen-approach)
6. [Implementation summary](#6-implementation-summary)
7. [Verification](#7-verification)
8. [Known limitations & future work](#8-known-limitations--future-work)
9. [References](#9-references)

Supporting material: [`issue.md`](issue.md) (raw issue text + requirements
table) and [`research.md`](research.md) (sourced external facts).

---

## 1. What was asked

The issue (Russian, translated in [`issue.md`](issue.md)) asks for:

1. An **animated retrowave/synthwave background** — the iconic 1980s aesthetic
   with a receding neon grid and a retro sun.
2. Specifically: a **perspective grid** and a **sunset with horizontal scan lines**
   matching the reference thumbnail.
3. **Forward compatibility**: the background system must support **dynamic switching
   per level/progress** in the future.

Full requirement table: [`issue.md §Extracted Requirements`](issue.md#extracted-requirements).

---

## 2. Problem analysis

This looks like a purely visual addition, but several sub-problems need careful
thought:

| Sub-problem | Core question | Resolution |
|---|---|---|
| **A. Rendering layer** | How does a 2D animated background sit behind a 3D game scene? | `CanvasLayer(layer=-1)` + `Environment.BG_CANVAS` |
| **B. Shader approach** | Per-frame GDScript drawing vs GPU shader? | GPU canvas-item shader driven by `TIME` |
| **C. Back panel visibility** | Opaque panel hides background; remove it or keep it? | Keep, but set 72 % alpha so the glow bleeds through |
| **D. Swappability** | How to theme-switch with zero runtime cost? | Palette as shader uniforms; swap dict in GDScript |
| **E. CI compatibility** | Background must not break the headless logic test | Guard against null shader in headless; logic test is unaffected |
| **F. Web export** | Does the shader work in the GL Compatibility / WebGL renderer? | Yes — only GLSL ES 1.0 built-ins used |

The non-obvious problem is **A**: Godot's 3D viewport normally writes a solid
clear colour over everything.  Setting `Environment.background_mode = BG_CANVAS`
switches the 3D clear to "composited on top of the 2D canvas", which is the only
correct way to show a CanvasLayer background behind 3D content.

---

## 3. Prior art & existing components

See [`research.md §4`](research.md#4-existing-components-considered) for the
full table.  Key findings:

* **[Perspective Grid Animated — Godot Shaders](https://godotshaders.com/shader/perspective-grid/)**:
  The canonical reference for UV-based perspective grids in Godot canvas shaders.
  Pattern adopted; code written fresh to combine grid + sun in one pass.

* **[Retro Sun — Godot Shaders](https://godotshaders.com/shader/retro-sun/)**:
  Radial disc + `mod()`-based scanline bands.  Pattern adopted.

* **No off-the-shelf Godot retrowave background asset** was found in the
  Asset Library at time of writing.  Writing the shader in-project is both
  smaller and more flexible than a third-party addon.

---

## 4. Options considered

### Rendering approach

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Animated sprites / PNGs | Simple | Not procedural; large files; can't colour-shift easily | ❌ |
| GDScript `draw_*()` on a CanvasItem | No shader needed | CPU-bound, every frame, poor on Web | ❌ |
| **Canvas-item GPU shader** | 60 fps with zero CPU, infinitely looping, all maths in GLSL | Requires GLSL knowledge | ✅ **chosen** |
| 3D geometry background (skybox) | True 3D perspective | Doesn't match 2D retrowave pixel aesthetic | ❌ |

### Swappability mechanism

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Load a different shader file per theme | Maximum flexibility | Load stall, more files | Maybe later |
| **Shader uniforms per theme** | Instant switch, one shader | Shader must expose all colour params | ✅ **chosen** |
| Multiple CanvasLayer nodes | Simple GDScript | Memory; "pop" between themes | ❌ |

---

## 5. Chosen approach

```
CanvasLayer (layer = -1)               ← sits behind the 3D viewport
  └── ColorRect (full screen)
        └── ShaderMaterial
              └── retrowave_background.gdshader
                    ├── upper half: gradient sky + retro sun + scanlines
                    └── lower half: perspective grid + glow + fog
```

3D environment uses `BG_CANVAS` so the transparent 3D clear lets the canvas
layer show through.  The existing back panel is kept but made 72 % opaque so
the neon glow still bleeds around the candy-ball play field.

Three built-in colour palettes live in `Background.gd`:
- `THEME_RETROWAVE` — default neon magenta + orange sunset
- `THEME_PLASMA` — cyan/teal midgame
- `THEME_NEON` — hot-pink / lime-green endgame

---

## 6. Implementation summary

### New files

| File | Purpose |
|------|---------|
| `shaders/retrowave_background.gdshader` | Single-pass canvas shader: sky gradient, retro sun with scanlines, perspective grid with glow |
| `scripts/Background.gd` | Node that owns the CanvasLayer, ColorRect, and ShaderMaterial; exposes `set_theme()` |

### Modified files

| File | Change |
|------|--------|
| `scripts/Game.gd` | Added `_build_background()` call in `_ready()`; switched 3D environment to `BG_CANVAS`; made back panel 72 % transparent; updated module doc comment |

### Key design decisions (with rationale)

1. **One shader file, all params as uniforms** — lets `set_theme()` be a simple
   dict iteration; avoids shader compilation stalls at theme-switch time.

2. **Perspective grid maths in the shader, not GDScript** — the grid is
   calculated every fragment (pixel) on the GPU; no CPU geometry generation.

3. **Scanlines on the lower half of the sun only** — matches the reference image;
   the upper half of the sun glows cleanly without stripes.

4. **Vignette** — a subtle brightness falloff at the screen edges keeps the
   player's eye on the central play field.

5. **72 % alpha on the back panel** — the dark backdrop keeps candy balls readable
   against the bright background, while allowing the neon glow to show at the
   borders.

---

## 7. Verification

### Headless CI test

The headless logic test (`tests/test_game_logic.gd`) drives the fall loop for
4000 steps without a display.  The background is initialised in `_ready()` but
neither renders nor allocates GPU resources in headless mode.  A null-guard
around the shader load (`if shader == null: return`) prevents any crash if
the resource fails to import headlessly.

The test checks only gameplay invariants (piece validity, settled-grid integrity,
line-clear progress) and is entirely unaffected by visual changes.

### Visual inspection

Build the project with Godot 4.5 and open it in the editor or export to Web.
Expected result:
- Lower half: magenta neon grid scrolling toward the viewer.
- Upper half: orange/yellow sun with horizontal dark stripes; deep violet sky above.
- Candy balls rendered over a semi-transparent dark panel; neon glow visible at edges.
- Animation loops seamlessly with no visible seam or stutter.

---

## 8. Known limitations & future work

| Limitation | Mitigation / Future work |
|------------|--------------------------|
| Theme switch is instantaneous (no crossfade) | Add a tween that lerps uniform values over 0.5–1 s |
| Only 3 built-in themes | Load external `.tres` ShaderMaterial resources for unlimited themes |
| `grid_speed` is constant | Drive it from `_lines` count for a "speed-up as you clear lines" feel |
| Scanline bands are static (same position regardless of TIME) | Animate band offset with `TIME * slow_speed` for subtle movement |
| No stars or particle effects in the sky | Add a Godot `GPUParticles2D` star field on a CanvasLayer between -2 and -1 |

---

## 9. References

1. [Godot 4 Environment — BG_CANVAS](https://docs.godotengine.org/en/stable/classes/class_environment.html#class-environment-constant-bg-canvas)
2. [Godot 4 CanvasLayer](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
3. [Godot 4 ShaderMaterial](https://docs.godotengine.org/en/stable/classes/class_shadermaterial.html)
4. [Godot Shaders — Perspective Grid Animated](https://godotshaders.com/shader/perspective-grid/)
5. [Godot Shaders — Retro Sun](https://godotshaders.com/shader/retro-sun/)
6. [Godot Shaders — Scan Lines](https://godotshaders.com/shader/scan-lines/)
7. [Retrowave colour palette guide — retrowave.com](https://retrowave.com/the-ultimate-outrun-color-palette-guide-for-retro-vibes/)
8. [Synthwave aesthetics — Fandom Wiki](https://aesthetics.fandom.com/wiki/Synthwave)
9. [Canvas item shaders reference — Godot 4](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
10. [Introduction to Shaders in Godot 4 — Kodeco](https://www.kodeco.com/43354079-introduction-to-shaders-in-godot-4/page/4)
