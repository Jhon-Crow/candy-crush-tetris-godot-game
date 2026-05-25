# Issue #7 — Add Toggle Between Automatic and Manual Tetris Control

## Original issue text (translated from Russian)

> **Add toggle between automatic and manual control of Tetris**
>
> Control of piece falling — with arrows and WASD; can enable automatic mode
> with Space.
>
> At the bottom center there should be a button (checkbox) "Автоматически"
> (Automatically) that shows the status or toggles by click/tap.
>
> For the mobile version, add arrow control buttons left and right of the
> game field.
>
> Implement the logic of automatic control of the falling — toward where the
> height is smallest and where the contact area of the falling piece with
> existing pieces is greatest, i.e. so that it perfectly fits into the slots.
>
> And implement it.

## Parsed requirements

| # | Requirement | Type |
|---|-------------|------|
| 1 | Arrow keys (←→↑↓) and WASD to move/accelerate the active piece | Keyboard input |
| 2 | Space bar toggles auto-play on/off | Keyboard input |
| 3 | "Автоматически" button/checkbox at bottom-centre of screen | UI element |
| 4 | Button shows current mode and toggles on click/tap | UI element |
| 5 | On-screen arrow buttons left/right of game field for mobile | Touch/mobile UI |
| 6 | Auto-player logic: prefer low column height + maximum contact area | AI algorithm |

## Status of existing implementation

The existing `Game.gd` already has:
- A four-feature heuristic auto-player (tuned weights from genetic algorithm)
- Auto-player that targets lowest aggregate height + most line clears + least
  holes + least bumpiness
- `auto_play` boolean export variable (controllable from Godot Inspector)

Missing:
- All keyboard input handling (`_unhandled_input` / `_input`)
- Space to toggle `auto_play`
- On-screen UI "Автоматически" toggle button
- Mobile on-screen directional buttons
