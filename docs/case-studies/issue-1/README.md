# Case study — issue #1: "Candy Crush + Tetris" in Godot

A deep-dive write-up of how issue [#1](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/1)
was analysed and implemented. It is meant to be read top-to-bottom:

1. [What was asked](#1-what-was-asked)
2. [Problem analysis](#2-problem-analysis)
3. [Prior art & existing components](#3-prior-art--existing-components)
4. [Options considered](#4-options-considered)
5. [Chosen approach](#5-chosen-approach)
6. [Implementation summary](#6-implementation-summary)
7. [Verification](#7-verification)
8. [Known limitations & future work](#8-known-limitations--future-work)
9. [References](#9-references)

Supporting material: [`issue.md`](issue.md) (raw issue text + requirements
table) and [`research.md`](research.md) (sourced external facts).

## 1. What was asked

The issue (Russian, translated in [`issue.md`](issue.md)) asks for **the most
primitive** "Candy Crush + Tetris": tetromino figures made of **multicoloured
balls** that **fall on their own** (no player control yet), with an *optional*
**automatic control** of the falling figures. Constraints and extras:

* Built in **Godot**.
* 2D gameplay but rendered in a **3D scene** (so visuals can be elaborated later).
* Exported as **HTML5**, to **GitHub Pages** if possible.
* Ideally **CI/CD to itch.io**, with instructions to connect one's own itch.io.
* **Screenshots in the comments.**
* Plus the standing request to compile a **case study** and **propose solutions,
  including known components/libraries**.

The full requirement breakdown (R1–R11) lives in
[`issue.md`](issue.md#extracted-requirements).

## 2. Problem analysis

The brief looks like one task but is really **four loosely-coupled problems**,
each with its own risk:

| Sub-problem | Core risk | Verdict |
|---|---|---|
| **A. Game logic** (fall / lock / clear) | Easy, but no input + straight fall ⇒ lines rarely clear, looks dead | Needs an auto-player to be visibly "alive" |
| **B. 2D-in-3D rendering** | Over-engineering; using 3D where 2D is natural | Use real 3D nodes (sphere meshes, lights) but an orthographic top-down view |
| **C. Web export on GitHub Pages** | **Highest risk** — threaded Godot Web builds need COOP/COEP headers Pages cannot set | Single-threaded export (Godot 4.3+) |
| **D. CI/CD to Pages + itch.io** | Secrets handling, preset-name mismatches, Jekyll mangling | Follow the community-standard pattern |

The non-obvious insight is **C**: a naïve "export to HTML5 and push to Pages"
produces a **blank screen** on GitHub Pages because of `SharedArrayBuffer`. This
single fact drives most of the technical decisions (see
[`research.md` §1](research.md#1-godot-web-html5-export-and-the-sharedarraybuffer-problem)).

The second non-obvious point is **A**: "figures fall, no control" literally
implemented means pieces pile up in the centre and the board resets without ever
clearing a line — visually boring and hard to test. The issue's own escape hatch
("you can enable automatic control of the falling figures") resolves this: an
**auto-player** makes the demo clear lines and gives the headless test something
meaningful to assert.

## 3. Prior art & existing components

Surveyed before building (details + links in
[`research.md`](research.md)):

* **Godot single-threaded Web export** (Godot 4.3+, `variant/thread_support=false`)
  — the official, header-free way to host on GitHub Pages. *Adopted.*
* **`coi-serviceworker` / [`nisovin/godot-coi-serviceworker`](https://github.com/nisovin/godot-coi-serviceworker)**
  — client-side COOP/COEP injection for *threaded* builds. *Considered, rejected*
  (extra reload + service worker, unnecessary once single-threaded).
* **[`abarichello/godot-ci`](https://github.com/abarichello/godot-ci)** — the
  community-standard Docker image + Actions templates for exporting Godot and
  deploying to Pages/itch.io. *Pattern adopted; image not used directly* (we pin
  the official Godot binary by URL instead — see [§4](#4-options-considered)).
* **`butler`** — itch.io's official uploader; the only supported way to publish
  to itch.io from CI. *Adopted.*
* **Four-feature Tetris placement heuristic** (Code My Road's near-perfect
  player) — the auto-player's scoring/weights. *Adopted.*
* **Existing Godot Tetris / match-3 clones** — full 2D games with input and their
  own scene trees; none fit the "balls, 3D scene, no input, auto-fall" brief.
  *Not reused* — the from-scratch core is smaller and clearer.

## 4. Options considered

### Web hosting / threading

| Option | Works on GitHub Pages? | Cost | Decision |
|---|---|---|---|
| Threaded export, no headers | ❌ blank screen | — | rejected |
| Threaded + `coi-serviceworker` | ✅ | extra reload, SW upkeep | rejected |
| Threaded + custom host with headers | ✅ | not Pages; infra | rejected |
| **Single-threaded export (4.3+)** | ✅ no headers | possible audio glitches (no audio here) | **chosen** |

### CI tooling

| Option | Pros | Cons | Decision |
|---|---|---|---|
| `barichello/godot-ci` Docker image | batteries included | image-tag drift, less transparent | pattern only |
| **Official Godot binary + templates by URL** | pinned to `4.5.2`, transparent, no image | a few more lines of YAML | **chosen** |

### Rendering

| Option | Pros | Cons | Decision |
|---|---|---|---|
| 2D nodes (`Sprite2D`) | simplest | violates "use a 3D scene" | rejected |
| **3D nodes, orthographic camera** | satisfies brief, real lights/shadows, easy to upgrade visuals | slightly more setup | **chosen** |
| 3D perspective camera | flashier | distorts a 2D grid | rejected |

### Auto-player

| Option | Pros | Cons | Decision |
|---|---|---|---|
| None (straight fall) | literal "no control" | never clears lines, looks dead, untestable | rejected |
| **Four-feature heuristic (column target)** | cheap, clears lines, easy to test | not optimal play | **chosen** |
| El-Tetris (6 features) / search over rotations | stronger play | overkill for "most primitive", needs rotation | future work |

## 5. Chosen approach

* **One scene, one script.** `scenes/Main.tscn` is a single `Node3D` running
  `scripts/Game.gd`, which **builds the entire scene in code** (camera, lights,
  back panel, HUD, balls). This keeps the whole game in one reviewable file and
  makes the headless test trivial to drive.
* **2D gameplay on a 3D stage.** An `8×16` grid lives in the world XY-plane at
  `z=0`. Each ball is a `MeshInstance3D` + `SphereMesh` with a glossy
  `StandardMaterial3D`; an **orthographic** `Camera3D`, a key/fill
  `DirectionalLight3D` pair with soft shadows, and a `WorldEnvironment` sell the
  "candy" look — all upgradeable later without touching game logic.
* **Header-free Web build.** The `Web` preset exports **single-threaded**
  (`variant/thread_support=false`) so it runs on GitHub Pages with no
  COOP/COEP headers, using the **GL Compatibility** renderer (best WebGL support).
* **Auto-player as the "automatic control".** Each spawn, `_best_target_column()`
  scores every legal landing column with the four-feature heuristic and the piece
  slides toward the winner as it falls. Toggled by `@export var auto_play`.
* **Two workflows.** `ci.yml` runs the headless invariant test on every push/PR;
  `deploy.yml` exports the Web build on every push/PR (uploaded as an artifact)
  and, on `main`, deploys to Pages and — when configured — publishes to itch.io.

## 6. Implementation summary

| Requirement | Where | Notes |
|---|---|---|
| R1 multicoloured balls | `Game.gd` `SHAPES`, `COLORS`, `_make_ball` | 7 tetromino shapes, 7-colour palette, glossy material |
| R2 automatic fall, no input | `_process` / `_step` | fixed-tick fall + smooth glide; zero input handlers |
| R3 candy flavour + line clear | `_make_ball`, `_clear_full_rows` | rows above shift down, re-check same index |
| R4 optional auto control | `auto_play`, `_best_target_column`, `_score_placement` | four-feature heuristic |
| R5 Godot | `project.godot` | Godot 4.5, GL Compatibility |
| R6 2D-in-3D | `_build_camera/_build_lights`, sphere meshes | orthographic, real shadows |
| R7 HTML5 | `export_presets.cfg` `Web` | single-threaded |
| R8 GitHub Pages | `deploy.yml` `deploy-pages` | official Pages workflow + `.nojekyll` |
| R9 itch.io CI/CD | `deploy.yml` `publish-itch` + README | `butler`, gated on repo variables |
| R10 screenshots | issue/PR comments + `docs/screenshots/` | rendered offscreen + real browser |
| R11 case study | this folder | issue.md / research.md / README.md |

Key parameters: grid `8×16`, `FALL_INTERVAL=0.30 s`, heuristic weights
`-0.51 / 0.76 / -0.36 / -0.18`.

## 7. Verification

* **Headless logic test** (`tests/test_game_logic.gd`) drives the fall loop for
  4000 steps and asserts the invariants — active piece always valid, settled
  balls never overlap or escape the grid, and the spawn→lock→clear loop makes
  progress (observed: up to 5 lines cleared). Runs in CI.
* **Clean-room export** verified the CI command sequence (`--import` then
  `--export-release "Web"`) produces `index.html` + `index.wasm`.
* **Real-browser check** — the single-threaded build was loaded in headless
  Chromium (Playwright) with **0 console errors**, confirming the GitHub-Pages
  compatibility claim. See `docs/screenshots/web-browser.png`.
* **Visuals** rendered offscreen via `xvfb` + Mesa llvmpipe — see
  `docs/screenshots/gameplay-1.png`, `gameplay-2.png`.

## 8. Known limitations & future work

* **No player input yet** — by design ("most primitive"). Adding rotation + soft
  drop is the obvious next step and would let the auto-player search rotations.
* **No match-3 / candy mechanics** — only Tetris-style full-row clearing. A true
  "Candy Crush" colour-match clear is a natural follow-up.
* **No audio** — convenient, since it sidesteps the single-threaded web-audio
  glitch noted in [`research.md` §1](research.md#the-chosen-fix--single-threaded-export-godot-43).
* **Heuristic only picks a column** — a stronger agent (El-Tetris's six
  Dellacherie features or a 2-piece search) is future work.
* **itch.io publish is opt-in** — skipped unless `ITCH_USER`/`ITCH_GAME` repo
  variables and the `BUTLER_CREDENTIALS` secret are set (see the README).

## 9. References

See [`research.md` §Sources](research.md#sources) for the full annotated list.
Highlights:

* Godot — [Web Export in 4.3](https://godotengine.org/article/progress-report-web-export-in-4-3/)
* [`abarichello/godot-ci`](https://github.com/abarichello/godot-ci) — CI pattern for Godot → Pages/itch.io
* Code My Road — [Tetris AI – The (Near) Perfect Player](https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/)
* [`nisovin/godot-coi-serviceworker`](https://github.com/nisovin/godot-coi-serviceworker) — the rejected threaded-build workaround
