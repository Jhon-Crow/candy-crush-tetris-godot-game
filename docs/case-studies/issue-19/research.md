# Research: OOP Architecture for Godot Games

## GDScript OOP Patterns

GDScript fully supports OOP with `class_name`, inheritance (`extends`), and composition.

### Key Patterns in GDScript

1. **Named Classes with `class_name`:** Makes classes accessible globally without explicit `load()`.
2. **Composition over Inheritance:** Godot's node tree encourages composition.
3. **Signals:** Decouple components (e.g., `signal piece_locked`, `signal lines_cleared`).
4. **Resources:** Data containers that can be saved/loaded.

## Godot Project Structure Best Practices

From Godot documentation and community standards:
- One script per logical concept
- Scripts in `scripts/` directory, organized by feature
- Scenes in `scenes/` directory
- Tests in `tests/` directory

## Proposed Decomposition

### Modules to Extract

| File | Responsibility | ~Lines |
|------|---------------|--------|
| `scripts/Board.gd` | Grid state, settled cells, row clearing | ~120 |
| `scripts/Piece.gd` | Active piece state, movement, placement validation | ~80 |
| `scripts/BallFactory.gd` | Creating ball nodes and materials | ~80 |
| `scripts/AutoPlayer.gd` | Heuristic AI for piece placement | ~80 |
| `scripts/SpecialEffects.gd` | Bomb, rainbow, freeze, lightning effects | ~90 |
| `scripts/HUD.gd` | Labels, score display, freeze indicator | ~60 |
| `scripts/SceneBuilder.gd` | Camera, lights, environment, back panel | ~60 |
| `scripts/Game.gd` | Main orchestrator (thin) | ~100 |

### Benefits

1. **Fewer conflicts:** Each feature lives in its own file
2. **Better testability:** Each class can be tested in isolation
3. **Clear ownership:** Developers can work on different systems simultaneously
4. **OOP principles:** Single Responsibility Principle per file

## Known Libraries / Tools

- **GUT (Godot Unit Test):** Popular testing framework for GDScript
- **gdlint:** GDScript linter
- **Godot's built-in headless mode:** Already used in CI for testing

## References

- [Godot GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [Godot Project Organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)
- [Godot Autoloads vs Class](https://docs.godotengine.org/en/stable/tutorials/best_practices/autoloads_versus_internal_nodes.html)
