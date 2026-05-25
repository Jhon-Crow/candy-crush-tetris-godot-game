# Case Study — Issue #7: Toggle Between Automatic and Manual Tetris Control

## Problem statement

The game previously had only an automatic mode (the AI steered each piece)
with no way for a human player to take control. The issue requested:

1. **Keyboard controls** — arrow keys and WASD to move the active piece left/right,
   soft-drop (↓/S) and hard-drop (↑/W) to control fall speed.
2. **Space to toggle** — pressing Space (or Enter) switches between auto and manual
   mode on the fly.
3. **On-screen "Авто" toggle** — a `CheckButton` at the bottom centre of the
   screen that shows the current mode and toggles it on click or tap.
4. **Mobile arrow buttons** — four `Button` nodes (◀ ▼ ▶ ▲) positioned beside the
   game field for touch/mobile play.
5. **Improved auto-play AI** — the existing 4-feature heuristic was augmented with
   an explicit _contact-area_ term so the AI prefers placements that slot snugly
   into gaps.

## Solution overview

All changes are confined to `scripts/Game.gd` (and the corresponding headless
test in `tests/test_game_logic.gd`).

### Keyboard input

`_unhandled_input()` handles one-shot actions: Space/Enter toggles auto-play;
↑/W performs a hard drop (when in manual mode); ←/A and →/D shift the piece one
column immediately on key-down.

Soft-drop is handled in `_process()` by polling
`Input.is_action_pressed("ui_down")` — while the key is held the fall interval
is reduced from 0.30 s to 0.06 s.

Godot's built-in action names (`ui_left`, `ui_right`, `ui_up`, `ui_down`,
`ui_accept`) cover both arrow keys and WASD automatically without needing any
`InputMap` configuration.

### On-screen toggle button

A `CheckButton` is created in `_build_hud()`:
- Anchored to the bottom-centre of the viewport.
- Its `toggled` signal directly sets `auto_play` on the game node.
- When `_toggle_auto_play()` is called (from keyboard), it syncs
  `_auto_button.button_pressed` so the button always reflects the current state.

### Mobile arrow buttons

Four `Button` nodes are created in `_build_mobile_buttons()`:
- **◀** (left) and **▶** (right): placed on the left/right edges of the screen,
  vertically centred. Pressing them sets `_manual_dx` which `_step()` applies on
  the next tick.
- **▼** (soft-drop): bottom-left. Uses `button_down`/`button_up` signals to set
  the `_soft_drop` flag, matching keyboard soft-drop behaviour.
- **▲** (hard-drop): bottom-right. Calls `_hard_drop()` on press.

All buttons also respond to mouse clicks, so they work for both desktop and
mobile players.

### Ghost piece

A row of translucent sphere meshes is added to preview where the active piece
will land. The ghost is repositioned each frame in `_update_ghost()` by finding
the lowest valid row for the current piece base.

### Improved AI: contact-area term

The new `_contact_area(base, occ)` function counts how many faces of the placed
piece touch either the floor or an already-occupied cell. This is added to
`_score_placement()` with weight `W_CONTACT = 0.20`, complementing the existing
aggregate-height / lines / holes / bumpiness terms. The result is that the AI
prefers pieces that slot neatly into concavities in the stack.

## Testing

`tests/test_game_logic.gd` was extended with four new test sections:

1. **Auto-play invariants** — same as before (piece always valid, grid never
   corrupted, lines do clear).
2. **Manual movement** — verifies `_try_move(-1)` decreases the column and
   `_try_move(1)` increases it; piece remains valid; hard drop produces a new
   valid piece.
3. **Toggle** — two calls to `_toggle_auto_play()` restore the original mode.
4. **Contact-area scoring** — a partially-filled board is constructed; the test
   asserts that placing a piece over the gap scores higher than placing it over
   empty space.

## Trade-offs and future work

| Decision | Rationale |
|----------|-----------|
| No piece rotation | Consistent with the existing codebase; adding rotation (wall kicks, rotation state) would be a separate issue. |
| Per-step left/right vs DAS repeat | Simpler; a full DAS (Delayed Auto-Shift) system is straightforward to add if responsiveness is a concern. |
| `CheckButton` for Авто toggle | Native Godot control; looks and feels like a standard toggle. A custom-styled button could be added later. |
| Mobile buttons on every platform | Simplest implementation; buttons could be hidden on non-touch platforms using `OS.has_touchscreen_ui_hint()`. |
