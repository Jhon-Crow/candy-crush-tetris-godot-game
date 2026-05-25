# Case Study: Issue #19 — OOP Refactor to Reduce Merge Conflicts

## Problem

The entire game lives in a single 666-line `scripts/Game.gd`. Every concurrent PR touches this file, resulting in merge conflicts on every feature branch.

## Root Cause

Monolithic architecture: board logic, rendering, AI, special effects, and HUD are all in one file with no separation of concerns.

## Solution

Split `Game.gd` into 7 focused modules using GDScript OOP (`class_name`):

| Module | Purpose |
|--------|---------|
| `Board.gd` | Grid data, settled cells, row clearing |
| `Piece.gd` | Active piece position, shape, movement |
| `BallFactory.gd` | 3D ball mesh + material creation |
| `AutoPlayer.gd` | Heuristic AI (column scoring) |
| `SpecialEffects.gd` | Bomb/Rainbow/Freeze/Lightning effects |
| `HUD.gd` | Score labels, freeze indicator |
| `SceneBuilder.gd` | Camera, lights, environment |
| `Game.gd` | Thin orchestrator |

## OOP Tests Added

- `tests/test_board_oop.gd` — Board isolation tests
- `tests/test_piece_oop.gd` — Piece movement/validity tests
- `tests/test_special_effects_oop.gd` — Per-effect isolation tests
- `tests/test_auto_player_oop.gd` — AI scoring tests
- Updated `tests/test_game_logic.gd` — Integration tests (unchanged behavior)

## Outcome

- Each new feature now adds/modifies one focused file
- PRs for different features (AI, effects, visuals, HUD) no longer conflict
- All existing tests pass
- New OOP tests verify component isolation
