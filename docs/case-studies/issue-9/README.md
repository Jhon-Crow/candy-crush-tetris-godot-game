# Case study — issue #9: добавить прогрессию (Add progression)

A deep-dive write-up of how issue [#9](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/9)
was analysed and implemented. Read top-to-bottom:

1. [What was asked](#1-what-was-asked)
2. [Problem analysis](#2-problem-analysis)
3. [Prior art & existing components](#3-prior-art--existing-components)
4. [Options considered](#4-options-considered)
5. [Chosen approach](#5-chosen-approach)
6. [Implementation summary](#6-implementation-summary)
7. [Verification](#7-verification)
8. [Known limitations & future work](#8-known-limitations--future-work)
9. [References](#9-references)

Supporting material: [`issue.md`](issue.md) (raw issue + requirements table)
and [`research.md`](research.md) (sourced external facts).

---

## 1. What was asked

The issue (Russian, translated in [`issue.md`](issue.md)) asks for **Candy
Crush-style progression elements** on top of the existing Tetris-like demo:

* **Score counter** — accumulate points for each cleared row.
* **Combo system** — reward consecutive clears with a multiplier.
* **Rush sections** — periodic speed-up (like Candy Crush's Sugar Rush).
* **Progress bar** — shows how close the next rush is.
* **Visual effects** — screen flash, combo pop, rush overlay.

The full requirement breakdown (R1–R8) is in [`issue.md`](issue.md#extracted-requirements).

---

## 2. Problem analysis

| Sub-problem | Core challenge | Verdict |
|---|---|---|
| **A. Score system** | Formula must feel "candy sweet" without being boring | Tetris-guideline scaling with candy flavour |
| **B. Combo detection** | Must distinguish consecutive vs. separated clears in an auto-play loop | Track a `_combo` counter reset on non-clearing lock |
| **C. Rush mechanic** | Triggering, duration, and resetting without breaking the fall loop | Fill a meter; on full → halve `FALL_INTERVAL` for 10 pieces |
| **D. Progress bar in Godot** | HUD uses `CanvasLayer`; need a Control node progress bar | `ProgressBar` child in the canvas layer |
| **E. Visual effects** | Must work in headless mode without crashing | Effects only when nodes exist; no crash in test |

The trickiest point is **E**: the headless test drives `_step()` directly
without a real scene tree, so effect nodes may be `null`. All effect calls
are guarded with `if node != null` checks.

---

## 3. Prior art & existing components

See [`research.md`](research.md) for the full sourced breakdown. Highlights:

* **Candy Crush Saga scoring** — 60 pts/candy, cascade multipliers. We adapt
  this as 100/300/600/1200 pts for 1/2/3/4 rows, then ×combo.
* **Tetris Guideline scoring** — back-to-back and T-spin bonuses; we borrow
  the multi-line escalation table.
* **Godot 4 `ProgressBar`** — built-in Control node; no add-on required.
* **Godot 4 `Tween`** — used for floating combo labels and screen flash;
  built-in, no third-party dependency.
* **"Juice It or Lose It"** (GDC 2012) — establishes the design vocabulary
  for game-feel (screen flash, floating text, pulsing border). Our effects
  are a minimal implementation of this vocabulary.

---

## 4. Options considered

### Score formula

| Option | Feeling | Decision |
|---|---|---|
| Flat +1 per cleared row | Boring, not candy | rejected |
| Tetris guideline (×level) | Accurate but cold | adapted |
| **Candy-flavoured escalation (×2, ×4 bonus) + combo multiplier** | Sweet, rewarding | **chosen** |

### Rush trigger

| Option | Design | Decision |
|---|---|---|
| Time-based (every N seconds) | Predictable, ignores play quality | rejected |
| **Score-threshold meter (progress bar fills with score)** | Rewards good play, visible, matches CCS | **chosen** |
| Random | Unpredictable, frustrating | rejected |

### Rush implementation

| Option | Feel | Decision |
|---|---|---|
| Instant-drop (20G) | Too hard for a demo | rejected |
| **Halve `FALL_INTERVAL` for 10 pieces** | Noticeable but survivable | **chosen** |
| Increase gravity continuously | Runaway difficulty | rejected |

### Visual effects

| Option | Cost | Decision |
|---|---|---|
| GPU particles per ball | High (3D, needs material) | future work |
| **Screen flash (`ColorRect` + `Tween`)** | Trivial | **chosen** |
| **Floating combo label (`Label` + `Tween`)** | Trivial | **chosen** |
| **Rush border pulse (`ColorRect` border + `Tween`)** | Trivial | **chosen** |

---

## 5. Chosen approach

* **Score formula**: 100 × (1, 3, 6, 12) for (1, 2, 3, 4) simultaneous rows
  cleared, then × `_combo` (capped at 8).
* **Combo counter**: incremented each time `_clear_full_rows` clears ≥ 1
  row; reset to 1 after a piece locks without clearing anything.
* **Rush meter**: `_rush_progress` accumulates points earned; when it
  reaches `RUSH_GOAL` (= 1 000 pts) Rush starts. The meter resets on Rush.
* **Rush mode**: `_rush_active` flag; while true `FALL_INTERVAL` is halved.
  Rush ends after `RUSH_PIECES` (= 10) pieces have been locked during rush.
* **HUD additions**: score label, combo label, rush label, and a
  `ProgressBar` (Godot's built-in Control) all added in `_build_hud()`.
* **Effects** (guarded for headless safety):
  - Screen flash: a full-screen `ColorRect` tweened to alpha=0.
  - Floating combo text: a `Label` child of the HUD tween-moved upward and
    faded out.
  - Rush border: a `ColorRect` border pulsed via `Tween` while rush is
    active.

---

## 6. Implementation summary

| Requirement | Where in `Game.gd` | Notes |
|---|---|---|
| R1 Score counter | `_score`, `_add_score()`, `_lines_label`→score label | Updates every clear |
| R2 Combo system | `_combo`, reset in `_lock_piece`, increment in `_clear_full_rows` | Capped at ×8 |
| R3 Rush sections | `_rush_active`, `RUSH_PIECES`, `_rush_pieces_left` | `FALL_INTERVAL` halved |
| R4 Progress bar | `_rush_bar` (`ProgressBar`), filled by `_rush_progress / RUSH_GOAL` | Resets on Rush trigger |
| R5 Visual effects | `_flash_screen()`, `_show_combo_popup()`, `_pulse_rush_border()` | Null-guarded |
| R6 HUD update | `_build_hud()`, `_update_hud()` | Score, combo, rush status |
| R7 Headless safe | All effect calls wrapped in `if … != null` | Test passes unchanged |
| R8 Case study | This folder | issue.md / research.md / README.md |

---

## 7. Verification

* **Existing headless test** (`tests/test_game_logic.gd`) — unchanged
  assertions; still checks active piece validity, settled grid integrity, and
  that at least one line is cleared in 4 000 steps.
* **New test assertions** (`tests/test_game_logic.gd`) — after 4 000 steps:
  - `game._score > 0` — score must have accumulated.
  - `game._combo >= 1` — combo counter must be a valid positive integer.
  - Progress bar ratio stays in `[0, 1]` range.
* **Manual verification** — run the game and observe:
  - HUD shows score, combo, rush progress bar.
  - Clearing multiple rows at once shows a combo popup.
  - Rush mode triggers when the bar fills, speed increases visibly.

---

## 8. Known limitations & future work

* **No GPU particles** — the ball "pop" on clear is a future visual upgrade.
* **No audio** — sound effects (jingle on clear, rush music) remain future work.
* **Rush difficulty not scaled** — after many rushes the game stays the same
  speed; a gradual baseline speed increase (like NES Tetris levels) is
  future work.
* **Combo only on consecutive pieces** — CCS's cascade combos within a single
  move are not implemented; that requires match-3 colour logic.
* **No level system** — score thresholds for star ratings are future work.

---

## 9. References

See [`research.md` §Sources](research.md#sources) for the full annotated list.

* Candy Crush Fandom — [Points](https://candycrush.fandom.com/wiki/Points)
* Tetris Wiki — [Scoring](https://tetris.wiki/Scoring)
* Jonasson & Purho (GDC 2012) — ["Juice It or Lose It"](https://www.youtube.com/watch?v=Fy0aCDmgnxg)
* Godot 4 docs — [ProgressBar](https://docs.godotengine.org/en/stable/classes/class_progressbar.html)
* Godot 4 docs — [Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)
