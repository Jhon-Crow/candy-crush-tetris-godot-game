# Issue #11 — Add Classic Candy Crush Special Balls

**Repository:** Jhon-Crow/candy-crush-tetris-godot-game  
**State:** Open  
**Author:** Jhon-Crow  
**URL:** https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/11

## Original Request (Russian)

> добавь классиечские для кенди краш особые шарики (бомбы, всех цветов одновременно, замораживающий время, вызывающий молнии и тп) и реализуй

## Translation (English)

> Add classic Candy Crush special balls (bombs, all-colors-at-once, time-freezing, lightning-striking, etc.) and implement them.

## Requirements Summary

1. **Bomb ball** — when locked into the settled grid, explodes and clears all balls within a radius around it.
2. **Rainbow / all-colors ball** — when locked, clears every settled ball that shares any color with the balls in the same piece, or simply clears the entire board row-by-row like a wildcard.
3. **Freeze / time ball** — when locked (or when spawned as part of a piece), temporarily slows or freezes the fall speed for a few seconds.
4. **Lightning ball** — when locked, fires a lightning bolt that clears the entire column it lands in.

## Scope

The game is a "Candy Crush + Tetris" hybrid implemented in Godot 4.5 (GDScript). Tetromino pieces made of multicoloured candy balls fall automatically. Special balls add power-up mechanics drawn from the Candy Crush Saga flavour of match-3 games.
