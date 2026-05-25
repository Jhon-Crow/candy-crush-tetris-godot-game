# Issue #15 — "добавь анимированный фон" (Add animated background)

## Original text (Russian)

> добавь анимированный фон в стиле ретровейв  
> сетка и закат как на референсе:  
> https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSOTutGxk7rNc6nAbONVl8tmBy2fFbMY9yK3A&s  
>
> учти что в будущем фоны должны будут динамически меняться по мере прогресса

## Translation (English)

> Add an animated background in the retrowave style.  
> Grid and sunset as in the reference image.  
>
> Keep in mind that in the future backgrounds should dynamically change as the player progresses.

## Extracted Requirements

| ID  | Requirement | Priority |
|-----|-------------|----------|
| R1  | Animated background in retrowave/synthwave visual style | must |
| R2  | Neon perspective grid (the "laser floor" receding into horizon) | must |
| R3  | Retro sunset — gradient disc with horizontal scanline stripes | must |
| R4  | Animation must loop seamlessly (no jump/stutter) | must |
| R5  | Design must be swappable for future per-level themes | must |
| R6  | Must not break the existing game logic or CI test | must |
| R7  | Must work in the Godot 4.5 HTML5 single-threaded export | must |
| R8  | Background must be behind game objects (candy balls, HUD) | must |

## Reference Image Analysis

The reference thumbnail shows classic "Outrun/synthwave" aesthetics:
- Lower half: a neon-grid plane receding into the horizon, glowing magenta/purple lines
- Upper half: a large retro sun disc, horizontal black stripes cut through it (scanlines)
- Sky gradient: deep indigo at top → hot magenta at horizon
- Colour palette: neon magenta, orange/yellow sun, deep violet sky
