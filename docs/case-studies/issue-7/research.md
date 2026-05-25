# Research Notes — Issue #7: Toggle Between Automatic and Manual Tetris Control

## 1. Input handling in Godot 4

### Keyboard input

Godot 4 provides two main methods for polling input events in a Node:

1. **`_input(event: InputEvent)`** — called on every input event; use for
   one-shot actions (key press, button click).
2. **`_unhandled_input(event: InputEvent)`** — same but only for events not
   already consumed by the UI layer; preferred when a CanvasLayer/Control node
   is present to prevent the game from responding when the UI is focused.
3. **`Input.is_action_pressed()`** in `_process()` — for held actions (fast-
   fall while a key is held).

The recommended pattern for a Tetris-style left/right shift is:
- On **key down** of Left/Right: shift once immediately, then start a
  delayed repeat timer (DAS — Delayed Auto-Shift).
- On **key up**: cancel the repeat.

For this primitive implementation, a simpler approach is used:
- Each `_step()` tick, check `Input.is_action_pressed("ui_left")` etc. and
  shift by one column if the user is holding the key (and auto-play is off).

Built-in Godot action names that work without any `project.godot` mapping:
- `ui_left` / `ui_right` — arrow left/right + A/D
- `ui_up` / `ui_down` — arrow up/down + W/S
- `ui_accept` — Enter / Space (space toggles auto)

References:
- https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
- https://docs.godotengine.org/en/stable/classes/class_input.html

### Touch / mobile input

For on-screen touch buttons in Godot, the best approach is to use
`TouchScreenButton` nodes. However, since this project builds its scene
entirely in GDScript, regular `Button` nodes with `pressed` signal connections
are simpler.

For web/mobile, the same `Button` that the desktop user clicks with a mouse
also works as a touch target, so there is no platform-specific branching needed.

## 2. On-screen toggle button (Автоматически checkbox)

In Godot 4, the `CheckButton` control provides exactly the semantics needed:
a toggle that shows a visual on/off indicator. Its `button_pressed` property
represents the toggle state and can be set programmatically.

Alternatively, a plain `Button` with `toggle_mode = true` can be used for a
simpler appearance.

Pattern to wire it up:
```gdscript
var toggle := CheckButton.new()
toggle.text = "Авто"
toggle.button_pressed = auto_play
toggle.toggled.connect(func(pressed): _set_auto_play(pressed))
layer.add_child(toggle)
```

Placement: bottom-centre of the canvas layer. With `AnchorPreset`
`ANCHOR_BOTTOM_CENTER` or fixed `position` based on viewport size.

## 3. Mobile on-screen arrow buttons

Requirements:
- Left arrow button to the left of the game field
- Right arrow button to the right of the game field
- Optionally: down arrow to accelerate falling
- Must also respond to touch events on mobile

Implementation approach in Godot 4:
```gdscript
# Create buttons with unicode arrows or emoji
var btn_left := Button.new()
btn_left.text = "◀"
# Connect button_down (held) and button_up (released) for smooth DAS, or
# use a simpler pressed-once approach by connecting "pressed" signal and
# applying a single column shift.
```

For proper mobile UX, buttons should be large (~80-100 px square) and placed
vertically centred beside the game grid.

## 4. Tetris AI — contact area heuristic

The issue requests that the auto-player prefer placements with maximum contact
area (the piece should "fit into the slots"). This corresponds to counting the
number of surfaces that touch either the floor or an existing settled cell.

### Existing implementation

The current 4-feature heuristic from Code My Road uses:
- **Aggregate height** (W = -0.51)
- **Complete lines** (W = +0.76)
- **Holes** (W = -0.36)
- **Bumpiness** (W = -0.18)

This already implicitly prefers fitting into slots (because it minimises holes
and bumpiness), but it does not explicitly count contact area.

### Adding explicit contact area scoring

Contact area = number of cells of the placed piece that are adjacent to an
already-occupied cell or the floor:

```gdscript
func _contact_area(base: Vector2i, occ: Array) -> int:
    var contacts := 0
    for o in _piece_offsets:
        var c := base + o
        # floor
        if c.y == 0:
            contacts += 1
        elif c.y > 0 and occ[c.y - 1][c.x]:
            contacts += 1
        # left neighbour
        if c.x > 0 and occ[c.y][c.x - 1]:
            contacts += 1
        # right neighbour
        if c.x < GRID_W - 1 and occ[c.y][c.x + 1]:
            contacts += 1
    return contacts
```

Weight recommendation: add `W_CONTACT * contact` with `W_CONTACT = +0.2` to
the existing scoring function to blend both strategies.

## 5. Piece rotation

The issue does not mention rotation, and the existing implementation has no
rotation. Adding full rotation support would significantly increase complexity
(wall kicks, rotation state machine). The initial implementation will omit it
(consistent with the current codebase), but left/right movement and faster-fall
(soft drop) via down key will be added.

## 6. Summary of proposed implementation

| Feature | Approach |
|---------|----------|
| Left/right manual move | Check `ui_left`/`ui_right` each `_step()` tick when `auto_play == false` |
| Faster fall (soft drop) | `ui_down` key halves `FALL_INTERVAL` while held |
| Hard drop (instant) | `ui_up` / W: drop piece immediately to the lowest valid row |
| Toggle auto-play | `ui_accept` (Space) toggles `auto_play`; updates UI button |
| "Авто" checkbox/button | `CheckButton` at bottom-centre of CanvasLayer |
| Mobile arrows | Two `Button` nodes ("◀" left, "▶" right) beside game field |
| AI contact area | New `_contact_area()` function added to `_score_placement()` |
