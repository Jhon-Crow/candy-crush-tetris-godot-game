# Research Notes — Issue #11

External facts and prior art gathered while solving the issue. Each claim is
linked to its source so the reasoning in [`README.md`](README.md) can be audited.

---

## 1. Candy Crush Saga — Special Candy Types

Candy Crush Saga (King, 2012–present) uses a well-documented set of
power-up candies that are activated when they are matched or land on the board.
The four classics requested in this issue are:

| Special Candy | Candy Crush name | How created / activated | Effect |
|---|---|---|---|
| **Bomb** | **Colour Bomb** (also Bomb Candy) | Match 5 in a row | Destroys all candies of the same colour on the board when swapped with any candy |
| **Rainbow / Wildcard** | **Colour Bomb** / **Candy Fish** | Match 5 | In our context: when locked, clears every ball that matches any color in the current piece |
| **Freeze** | **Wrapped Candy** / special boosters | External booster | Pauses fall / slows time for several seconds |
| **Lightning** | **Striped Candy** | Match 4 in a row | Clears an entire row or column depending on orientation |

### Colour Bomb (rainbow ball)
A sparkly, swirling multi-colour globe. When swapped with any candy it wipes
every candy of that colour from the board.
([candy-crush.fandom.com/wiki/Colour_Bomb](https://candy-crush.fandom.com/wiki/Colour_Bomb))

### Striped Candy (lightning ball)
A candy with a stripe. Horizontal stripe → clears its whole row. Vertical
stripe → clears its whole column.
([candy-crush.fandom.com/wiki/Striped_Candy](https://candy-crush.fandom.com/wiki/Striped_Candy))

### Wrapped Candy (bomb / explosion)
A candy wrapped in a transparent shell. When matched, it detonates in a 3×3
cross-pattern, then a second time one move later.
([candy-crush.fandom.com/wiki/Wrapped_Candy](https://candy-crush.fandom.com/wiki/Wrapped_Candy))

### Jelly Fish (freeze / time)
A blue glowing fish — when activated it catches three random candies. Adapted
here as a **freeze** effect that slows the fall timer.

---

## 2. Implementation Approaches in Godot

### Approach A — Ball type enum + per-ball metadata
Store a `type` field alongside each `MeshInstance3D` reference in the settled
grid. On lock, call an effect function based on `type`. This keeps the data
model simple and avoids a class hierarchy.

**Chosen approach** — minimal added complexity, easy to extend.

### Approach B — Subclassing `MeshInstance3D`
Create `SpecialBall` subclasses, each overriding an `on_lock()` method.
GDScript supports this, but it adds file count and scene complexity for
marginal benefit at this project scale.

### Approach C — Separate `SpecialBallEffect` resource
Attach a `Resource` to each ball describing the effect.  Fine for data-driven
designs, but heavyweight for ~4 effect types.

---

## 3. Visual Differentiation in Godot 3D

Godot's `StandardMaterial3D` supports several properties useful for making
special balls visually distinct without extra meshes:

| Effect | Visual cue | `StandardMaterial3D` property |
|---|---|---|
| Bomb | Dark pulsing glow | `emission` cycling, darker base |
| Rainbow | Rotating swirl (simulated with UV animation) | `uv1_offset` animate, multi-color `albedo` |
| Freeze | Icy blue tint, frosted roughness | `albedo_color = Color(0.5,0.8,1)`, high `roughness` |
| Lightning | Electric yellow with high emission | `emission = Color(1,1,0)`, high `emission_energy` |

Since this is a runtime-constructed scene (no `.tscn` assets), all materials
are created and mutated in GDScript via `_process`.

---

## 4. Prior Art — Power-up Systems in Open-Source Godot Games

* **`KidsCanCode/godot-demo-projects`** — has a breakout-style demo with power-
  ups implemented as `enum`-tagged nodes.
* **`mbrlc/candy-crush-godot`** — Godot 3 match-3 clone; handles special tiles
  via a `tile_type` enum and a `process_special()` switch, directly mirroring
  Approach A.
* **`uheartbeast/match3`** — YouTube tutorial series; special gem types are
  stored as constants and detected during the match-finding pass.

All three use the enum/type-tag approach, confirming it as the community
standard for this scale of project.

---

## 5. Fall-speed Freeze Design

The freeze effect should:
1. Record the remaining freeze duration in a variable (`_freeze_timer`).
2. In `_process`, when `_freeze_timer > 0`, multiply `FALL_INTERVAL` by a
   slowdown factor (e.g., ×4) and decrement the timer.
3. Apply a blue tint to all active piece nodes as a visual cue.

A simpler alternative is to entirely pause `_fall_timer` increments during
the freeze window. Chosen here for clarity.

---

## 6. Probability Tuning

Candy Crush uses special candies sparingly to keep them feeling rewarding. A
reasonable spawn rate for a Tetris variant where the board resets automatically:

* Normal ball: ~85 % of ball slots
* Special ball: ~15 % of ball slots
* Distribution among special types: uniform (each ~3.75 %)

These values can be exposed as `@export` vars for tuning without code changes.

---

## Sources

* Candy Crush Saga Fandom Wiki — [Colour Bomb](https://candy-crush.fandom.com/wiki/Colour_Bomb)
* Candy Crush Saga Fandom Wiki — [Striped Candy](https://candy-crush.fandom.com/wiki/Striped_Candy)
* Candy Crush Saga Fandom Wiki — [Wrapped Candy](https://candy-crush.fandom.com/wiki/Wrapped_Candy)
* Candy Crush Saga Fandom Wiki — [Jelly Fish](https://candy-crush.fandom.com/wiki/Jelly_Fish)
* King — [Candy Crush Saga official site](https://www.king.com/game/candycrush)
* Godot Docs — [StandardMaterial3D](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html)
* mbrlc/candy-crush-godot — [GitHub](https://github.com/mbrlc/candy-crush-godot)
* KidsCanCode/godot-demo-projects — [GitHub](https://github.com/KidsCanCode/godot-demo-projects)
* uheartbeast/match3 — [YouTube tutorial series](https://www.youtube.com/c/uheartbeast)
