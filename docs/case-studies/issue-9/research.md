# Research — Issue #9: Candy Crush Progression Mechanics

## 1. Candy Crush Saga progression systems

Candy Crush Saga (King, 2012–) uses a layered progression model built from five
core mechanics:

### 1.1 Score counter
- Every match awards base points: **60 pts per candy** in a 3-match, scaling
  by match length (4-match → 120, 5-match → 200+).
- Combo moves (chain reactions where newly settled candies form their own
  matches) multiply points.
- A star-rating threshold system gates level progress (1–3 stars based on
  score at level end).
- **Source:** King's official Candy Crush guide; fan wikis at
  <https://candycrush.fandom.com/wiki/Points>

### 1.2 Combo / streak system
- **Combo**: a single move triggering multiple successive cascade clears.
  Each cascade step adds a "x2", "x3", … multiplier overlay to the score.
- **Streak**: consecutive turns where the player clears at least one match.
  In some variants this unlocks colour bombs or fish candies.
- Well-known pattern: show a floating label ("x2 COMBO!") and a brief burst
  animation.
- **Analogues in Tetris:** back-to-back Tetris, T-spin chains, REN/B2B
  systems (Guideline Tetris since 2001).

### 1.3 Rush / Frenzy sections
- Starting around episode 20 in CCS, certain levels feature "Sugar Rush":
  the board speeds up or a time-limited free-play window opens after a goal.
- In Candy Crush **Jelly Saga** and **Soda Saga** variants, a "Jelly Rush"
  clears all remaining jelly at high score thresholds.
- The sensation is replicated in Tetris as "20G" gravity (pieces fall
  instantly) in guideline Tetris, or the increasing gravity in early
  *Tetris* (NES, 1989).
- For a Tetris-like game, a practical Rush implementation is a **fall-speed
  increase** triggered when a periodic score threshold is crossed, lasting
  for N pieces or M seconds, then reverting.

### 1.4 Progress bar
- CCS shows a coloured bar below the board; filling it by clearing moves
  triggers a "Sugar Rush" bonus.
- Progress is additive: every cleared candy or row contributes a fixed
  amount; bar resets at Rush trigger.
- Well-understood UI pattern: `ProgressBar` (Godot Control node) with a
  custom theme colour.

### 1.5 Visual effects
- Match pop: particles or scale-up-then-fade ("juice") animation.
- Clear flash: brief white/yellow flash on the board.
- Combo label: floating "+250 COMBO x3!" text that rises and fades.
- Rush overlay: pulsing border or background color shift.
- **Juice It or Lose It** (2012 GDC talk by Martin Jonasson & Petri Purho)
  establishes the design vocabulary for game-feel enhancements.
  <https://www.youtube.com/watch?v=Fy0aCDmgnxg>

---

## 2. Existing Godot components / libraries

### 2.1 Godot built-ins used directly
| Feature | Godot node/class | Notes |
|---|---|---|
| Progress bar | `ProgressBar` (Control) | Built-in, stylable |
| Floating labels | `Label` + `Tween` | Animate position & modulate alpha |
| Screen flash | `ColorRect` + `Tween` | Full-screen translucent rect fading |
| Particle pop | `GPUParticles3D` or `CPUParticles3D` | 3D particles at ball position |
| Score/combo text | `Label` | Same HUD canvas layer |

### 2.2 Third-party add-ons (considered, not required)
| Add-on | What it gives | URL |
|---|---|---|
| **Phantom Camera** | smooth camera shakes for hit-feedback | <https://github.com/ramokz/phantom-camera> |
| **Cyclops Game Effects** | pre-built juice particles/tweens for Godot 4 | <https://github.com/Firebelley/GodotFireParticleSet> (inspiration) |
| **GodotTween (chain)** | cleaner multi-step tween API | built into Godot 4 already |

All chosen effects can be built with Godot 4's built-in `Tween`, `Label`,
`ColorRect`, and `ProgressBar` — no third-party dependency needed.

---

## 3. Candy Crush score formula reference

The canonical score per line-clear in a Tetris analogue (following Tetris
guideline) is:

| Lines cleared at once | Base points | Tetris bonus |
|---|---|---|
| 1 (Single) | 100 × level | — |
| 2 (Double) | 300 × level | — |
| 3 (Triple) | 500 × level | — |
| 4 (Tetris) | 800 × level | 1 200 back-to-back |

Candy Crush's numeric rewards are proprietary; a reasonable candy-flavoured
mapping:
- **1 row** cleared → 100 pts
- **2 rows** cleared → 300 pts  (2× bonus)
- **3 rows** cleared → 600 pts  (2× bonus × 3)
- **4 rows** (full Tetris) → 1 200 pts (×4 bonus)
- **Combo multiplier** → score × combo_count (cap at ×8)

---

## 4. Rush / speed-up design reference

- **Candy Crush Saga Sugar Rush**: triggered by filling a meter, lasts ~5 s,
  extra points for everything cleared.
- **Practical Tetris analogue**: reduce `FALL_INTERVAL` by 40–50 % for the
  rush, revert after a fixed number of pieces or seconds.
- **Progress bar** fills by 1/RUSH_GOAL points per point earned; on full →
  Rush, reset bar.
- Design choice: **Rush lasts 10 pieces** (long enough to feel exciting,
  short enough to end before novelty wears off).

---

## Sources

1. Candy Crush Fandom wiki — Points:
   <https://candycrush.fandom.com/wiki/Points>
2. Tetris Guideline scoring (2009):
   <https://tetris.wiki/Scoring>
3. "Juice It or Lose It" (Jonasson & Purho, GDC 2012):
   <https://www.youtube.com/watch?v=Fy0aCDmgnxg>
4. Godot 4 docs — ProgressBar:
   <https://docs.godotengine.org/en/stable/classes/class_progressbar.html>
5. Godot 4 docs — Tween:
   <https://docs.godotengine.org/en/stable/classes/class_tween.html>
6. King (2012). *Candy Crush Saga*. iOS / Android / Facebook.
7. Nintendo (1989). *Tetris* (NES). Speed levels with gravity increase.
8. The Tetris Company (2009). *Tetris Guideline* — scoring, back-to-back.
