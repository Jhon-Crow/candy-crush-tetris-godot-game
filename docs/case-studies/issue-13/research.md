# Research notes — issue #13

## 1. Smooth falling / interpolation in Godot 4

### move_toward vs. lerp

`move_toward(target, step)` is a **linear** approach that stops exactly at the
target. It can produce a perceptible "snap" at the end because the last step is
capped. For smooth organic motion, **exponential smoothing** (`lerp`) is
preferred:

```gdscript
# Each frame, close a fixed fraction of the remaining distance.
node.position = node.position.lerp(target, 1.0 - exp(-speed * delta))
```

The `1 - exp(-speed * delta)` factor is **frame-rate independent** and gives a
natural ease-out without ever snapping, because it asymptotically approaches but
never exceeds the target.

References:
- Godot docs: [Vector3.lerp](https://docs.godotengine.org/en/stable/classes/class_vector3.html#class-vector3-method-lerp)
- Freya Holmér: *"Lerp smoothing is broken"* — argues for `exp`-based smoothing:
  `f = 1 - e^(-λΔt)` where λ controls the speed.
  <https://acegikmo.medium.com/the-right-way-to-lerp-in-unity-or-any-game-engine-10d6a07f2568>
- Ryan Juckett: *Critically Damped Ease-In/Ease-Out* for spring-like smoothing.

### Logical fall rate

Reducing `FALL_INTERVAL` from 0.30 s to a larger value (e.g. 0.45–0.60 s) gives
the glide more time to reach its target, making even a `move_toward` approach
look smooth. Alternatively, keeping `FALL_INTERVAL = 0.5` and using `lerp`
ensures the visual ball is always smoothly in transit between positions.

## 2. Material properties for subtle highlights in Godot 4

Godot 4's `StandardMaterial3D` key properties that control the glossy look:

| Property | Current | Suggested |
|---|---|---|
| `roughness` | 0.22 | 0.15 (glass stays specular, but clearcoat handles the top layer) |
| `metallic` | 0.0 | 0.05 |
| `rim` | 0.5 | 0.15 |
| `rim_tint` | 0.0 | 0.5 (blend rim with albedo so it's less harsh) |
| `emission_energy_multiplier` | 0.22 | 0.08 |
| `clearcoat` | — | 0.8 (sharp top-coat highlight) |
| `clearcoat_roughness` | — | 0.05 |

The clearcoat layer in Godot 4 adds a **second specular layer** on top of the
base material, like a lacquer coat. It uses a fixed Schlick Fresnel and does not
accumulate with the base highlight, so it prevents the harsh "blob of white"
look while still producing a crisp glass-like reflection.

References:
- Godot 4 docs: [StandardMaterial3D](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html)
- Godot 4 docs: [Rim parameter](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html#class-standardmaterial3d-property-rim)
- Godot 4 docs: [Clearcoat](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html#class-standardmaterial3d-property-clearcoat)

## 3. Crystal / gem appearance in Godot 4

### Transparency and refraction

`StandardMaterial3D` has built-in refraction support:
- `transparency = TRANSPARENCY_ALPHA` — enables alpha blending
- `refraction_enabled = true` — enables screen-space refraction
- `refraction_scale` — controls the strength of the refraction distortion
- `albedo_color.a` — controls alpha (0.0 = fully transparent, 1.0 = opaque)

For a crystal that *feels* solid but looks glassy:
- `albedo_color.a = 0.55` to `0.70` — semi-transparent enough to see through
- `refraction_scale = 0.04` to `0.08` — subtle warping of background
- `metallic = 0.1`, `roughness = 0.08` — very smooth surface

### Faceted geometry

Options for faceted crystal shapes in Godot 4 (all available as built-in mesh
types):

| Mesh | Notes |
|---|---|
| `SphereMesh` with flat shading | Set `flip_faces = false` and force flat normals via a `SurfaceTool`; or use a low-poly icosphere |
| `PrismMesh` | 3-sided prism — good for triangular crystals |
| `BoxMesh` subdivided | Low-poly cube with distinct face normals |
| Custom `ArrayMesh` | Full control; can build a gem silhouette in code |

The simplest approach that still looks "crystalline" without a custom mesh: use a
`BoxMesh` (6 flat faces → clearly faceted) scaled slightly non-uniformly and
combine with high clearcoat + refraction. The box approximates a rough gem cut.

An even simpler option: add a `SurfaceTool`-generated flat-shaded icosphere as
the mesh. This gives ~20 triangular facets and the geometry auto-generates facet
normals.

For this project we use a **PrismMesh** (triangular prism) as the crystal unit.
It is available in Godot 4, gives 5 clearly distinct flat faces visible from any
angle, and its triangular cross-section reads as "gem" or "crystal" instantly.
Alternatives like `CylinderMesh` with 6 sides (hexagonal prism) also work well.

References:
- Godot 4 docs: [StandardMaterial3D — Transparency](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html#class-standardmaterial3d-property-transparency)
- Godot 4 docs: [StandardMaterial3D — Refraction](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html#class-standardmaterial3d-property-refraction-enabled)
- Godot 4 docs: [PrismMesh](https://docs.godotengine.org/en/stable/classes/class_prismmesh.html)
- Godot 4 docs: [CylinderMesh](https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html)
- Game dev StackExchange: "How to make a glass material in Godot 4?"
  <https://gamedev.stackexchange.com/questions/204635>
- Godot forum: "Crystal/gem shader in Godot 4" — community recommendation is
  StandardMaterial3D with `refraction_enabled + clearcoat`.

### Lighting for crystal appearance

With transparent objects:
- **Ambient light** should be moderate (not too bright — otherwise transparency
  looks washed out).
- **Point lights** inside or near crystals produce the "internal glow" look;
  but since this project uses directional lights for the 3D-in-2D setup,
  increasing `emission` slightly (very low) gives inner glow.
- **Shadow casting** from transparent meshes should be disabled or reduced
  (`cast_shadow = SHADOW_CASTING_SETTING_OFF`) to avoid ugly blocky shadows from
  alpha-blended geometry.

## 4. Existing approaches / libraries

| Approach | Relevance |
|---|---|
| Godot built-in `StandardMaterial3D` | ✅ All needed features present |
| `SurfaceTool` flat-shaded mesh | ✅ Built-in, no addon needed |
| GodotShaders community shaders | ℹ️ Overkill — built-in mat handles this |
| Godot 4 shader language custom `spatial` shader | ℹ️ Alternative, more control |
| ProtonGraph / scatter plugin | ❌ Not relevant |

**Conclusion**: no external library is needed. Godot 4's `StandardMaterial3D`
with transparency + refraction + clearcoat, combined with a `PrismMesh` geometry
and exponential-lerp motion, fully addresses all three requirements of issue #13.
