# Case Study — Issue #11: Special Candy Balls

## Problem

The game lacked Candy Crush-style power-up balls. The issue requested:

* 💣 **Bomb** — explodes and clears nearby cells
* 🌈 **Rainbow** — clears all balls matching any color in the current piece
* ❄️ **Freeze** — temporarily slows the fall speed
* ⚡ **Lightning** — strikes and clears an entire column

## Solution Overview

### Data Model

A new `BallType` enum is added to `Game.gd`:

```gdscript
enum BallType { NORMAL, BOMB, RAINBOW, FREEZE, LIGHTNING }
```

Each ball slot in the settled grid and each active piece node is paired with
its `BallType` in parallel arrays (`_settled_types`, `_piece_types`).

### Spawn Logic

`_spawn_piece()` now randomly assigns a `BallType` to each ball with a tunable
probability (~15 % chance of any special ball per slot). Special balls get a
distinctive material so the player can see them.

### Effect Triggers

When `_lock_piece()` places a ball, its type is checked:

| Type | Effect |
|---|---|
| `BOMB` | Calls `_effect_bomb(cell)` — removes all settled balls within a Chebyshev radius of 2 |
| `RAINBOW` | Calls `_effect_rainbow(colors)` — removes all settled balls whose color matches any color in the locked piece |
| `FREEZE` | Sets `_freeze_timer` (default 4 s) — `_process` uses a slowed fall interval while the timer is positive |
| `LIGHTNING` | Calls `_effect_lightning(col)` — removes all settled balls in the same column |

### Visual Differentiation

Materials are constructed differently per type so special balls stand out:

| Type | Albedo | Emission | Roughness | Extra |
|---|---|---|---|---|
| Normal | Palette color | Palette color × 0.22 | 0.22 | — |
| Bomb | Dark grey | Red-orange × 2.0 | 0.55 | Pulsing emission in `_process` |
| Rainbow | White | Cycling rainbow × 1.5 | 0.15 | Color cycles in `_process` |
| Freeze | Icy blue | Cyan × 1.0 | 0.85 | — |
| Lightning | Yellow | Yellow × 3.0 | 0.10 | Fast pulse in `_process` |

### HUD Changes

The score line is extended to show the active freeze status and number of
special balls triggered.

## Trade-offs Considered

| Option | Decision |
|---|---|
| Subclass per ball type | Rejected — adds files for 4 trivial variations |
| Resource-based power-up data | Rejected — heavyweight for this scale |
| Enum + parallel arrays | **Chosen** — minimal and consistent with existing style |
| Full Candy Crush combos (special × special) | Deferred — out of scope for this issue |

## Testing

`tests/test_game_logic.gd` is extended with:

* A test that forces a bomb ball to lock and asserts that nearby cells are cleared.
* A test that forces a lightning ball and asserts the column is emptied.
* A test that forces a freeze ball and asserts `_freeze_timer` is set.
* A test that forces a rainbow ball and asserts matching-color cells are cleared.
* The existing grid-invariant checks continue to run and must pass after each effect.

## Files Changed

| File | Change |
|---|---|
| `scripts/Game.gd` | +BallType enum, special ball spawn, effect functions, animated materials |
| `tests/test_game_logic.gd` | +4 special-ball effect tests |
| `docs/case-studies/issue-11/` | New — this case study |
