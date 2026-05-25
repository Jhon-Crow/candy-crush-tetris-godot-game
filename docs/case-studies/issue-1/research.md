# Research notes — issue #1

External facts and prior art gathered while solving the issue. Each claim is
linked to its source so the reasoning in [`README.md`](README.md) can be audited.

## 1. Godot Web (HTML5) export and the `SharedArrayBuffer` problem

Godot 4.0–4.2 could only export multi-threaded Web builds. Those builds rely on
`SharedArrayBuffer`, which browsers only expose to **cross-origin isolated**
pages. A page is cross-origin isolated only when the server sends two response
headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

**GitHub Pages does not let you set custom response headers**, so a default
threaded Godot 4.2 export shows a blank screen with a `SharedArrayBuffer is not
defined` error when hosted there.
([gamineai.com](https://gamineai.com/help/godot-web-export-sharedarraybuffer-coop-coep-hosting-fix),
[godotengine/godot#85938](https://github.com/godotengine/godot/issues/85938),
[rafa.ee](https://www.rafa.ee/articles/deploying-godot-4-html-exports/))

### Workarounds for threaded builds (rejected here)

* **`coi-serviceworker`** — a service worker that re-fetches the page and injects
  the COOP/COEP headers client-side, faking cross-origin isolation on hosts that
  cannot set headers (such as GitHub Pages). Maintained for Godot as
  [`nisovin/godot-coi-serviceworker`](https://github.com/nisovin/godot-coi-serviceworker).
  Downsides: an extra reload, a service worker to manage, and it fails in some
  privacy modes.
* **PWA export** — Godot can emit a Progressive Web App whose service worker
  injects the headers, per the official report.
  ([godotengine.org](https://godotengine.org/article/progress-report-web-export-in-4-3/))

### The chosen fix — single-threaded export (Godot 4.3+)

At the end of the 4.2 cycle the Godot Foundation funded work to build the engine
**without threads** for the web, removing the `SharedArrayBuffer` requirement
entirely. Shipped in **Godot 4.3**, it is toggled by the export preset option
`variant/thread_support=false`. A single-threaded build runs on any static host
(GitHub Pages, itch.io, plain S3) with **no special headers**.
([godotengine.org "Web Export in 4.3"](https://godotengine.org/article/progress-report-web-export-in-4-3/),
[Godot forum](https://forum.godotengine.org/t/godot-4-3-will-finally-fix-web-builds-no-sharedarraybuffers-required/38885))

Trade-off noted by the Foundation: single-threaded builds can have audio
glitches on some machines, but they **fix** the long-standing Apple/iOS/macOS
web-audio problems. This project has no gameplay audio yet, so the trade-off is
strongly in favour of single-threaded for maximum host compatibility.

## 2. CI/CD: exporting Godot from GitHub Actions, publishing to itch.io

* **[`abarichello/godot-ci`](https://github.com/abarichello/godot-ci)** — the
  de-facto community standard: a Docker image with Godot + export templates and
  ready-made GitHub Actions / GitLab CI templates that deploy to GitHub Pages,
  GitLab Pages, and itch.io. ([GitHub Marketplace](https://github.com/marketplace/actions/godot-ci))
* **itch.io publishing uses `butler`**, itch.io's official command-line upload
  tool. The CI authenticates with an itch.io **API key** and pushes a *channel*,
  e.g. `butler push build/web user/game:html5`.
  ([abarichello/godot-ci](https://github.com/abarichello/godot-ci),
  [simondalvai.org](https://simondalvai.org/blog/godot-itchio-upload/),
  [vojtechstruhar.com](https://www.vojtechstruhar.com/blog/022-godot-itch-github-action/))
* **Gotchas confirmed and applied here**:
  * `export_presets.cfg` **must be committed** (not git-ignored) or CI cannot
    export.
  * The preset name passed to the CLI must match `export_presets.cfg`
    **case-sensitively**, and names with spaces must be quoted.
  * Godot 4 exports headlessly with `godot --headless --export-release "Web"
    path/index.html`.
  ([abarichello/godot-ci](https://github.com/abarichello/godot-ci))

This project does **not** depend on the `godot-ci` Docker image; it downloads the
official Godot binary + export templates by URL instead (fewer moving parts, no
image-tag drift, easy to pin to `4.5.2`). But the workflow follows exactly the
same pattern the community standard documents, so it is easy to migrate either
way.

### Why GitHub Pages deploys via the official Pages workflow

The deploy job uses `actions/upload-pages-artifact@v3` +
`actions/deploy-pages@v4` with `pages: write` / `id-token: write` permissions —
the modern "GitHub Actions" Pages source — rather than pushing to a
`gh-pages` branch. `.nojekyll` is created so Pages does not run Jekyll over the
WASM/JS build (Jekyll ignores files/dirs starting with `_` and can mangle the
output).

## 3. The auto-player heuristic ("automatic control of the falling figures")

The issue asks that the falling figures *can* be automatically controlled. A
well-known, cheap, and effective approach is a **one-piece placement heuristic**
that scores every legal landing position of the current piece by a weighted sum
of four board features and picks the best target column:

* **aggregate height** — sum of column heights (minimise),
* **complete lines** — rows that would be cleared (maximise),
* **holes** — empty cells with a filled cell above them in the same column
  (minimise),
* **bumpiness** — sum of absolute differences between adjacent column heights
  (minimise).

The exact weights used here — `-0.51, 0.76, -0.36, -0.18` — are the
genetic-algorithm-tuned values popularised by Code My Road's *"Tetris AI – The
(Near) Perfect Player"* (`{-0.510066, 0.760666, -0.35663, -0.184483}`), which can
clear lines almost indefinitely.
([codemyroad.wordpress.com](https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/))
The same four-feature formula is described in many independent write-ups.
([thawsitt.me CS221 paper](https://thawsitt.me/files/Tetris_AI_CS221_final_paper.pdf))

Because this build has no rotation and no player input yet, the auto-player only
chooses the **horizontal target column** and slides the piece toward it as it
falls — the minimal useful form of "automatic control". A fuller agent
(El-Tetris's six Dellacherie features, or a search over rotations) is noted as
future work but would be overkill for "the most primitive implementation".

## 4. Prior art: Godot Tetris / match-3 examples

Surveyed for reuse before writing from scratch:

* Numerous open-source **Godot Tetris** clones exist (e.g. genetic-algorithm
  agents such as [`CamGomezDev/SmartTetris`](https://github.com/CamGomezDev/SmartTetris)),
  but they are full 2D games with input handling and their own scene trees —
  none match the specific "balls in a 3D scene, no input, auto-fall" brief.
* Godot ships a first-party **GodotTetris**-style demo only as community assets;
  the official demo repo focuses on 2D.
* **Match-3 / Candy-Crush** Godot tutorials exist but solve a *different* core
  loop (swap-to-match), not gravity-stacked tetrominoes.

Conclusion: the gameplay is small enough (a few hundred lines) that a focused,
from-scratch implementation built directly on Godot's 3D nodes is clearer and
smaller than adapting a 2D clone. The reusable, non-trivial parts — the web
single-threaded insight, the Pages/itch.io pipeline, and the placement heuristic
— are taken from the prior art above.

## Sources

* Godot — [Web Export in 4.3 progress report](https://godotengine.org/article/progress-report-web-export-in-4-3/)
* GitHub issue — [godotengine/godot#85938 (run without threads/SharedArrayBuffer)](https://github.com/godotengine/godot/issues/85938)
* GitHub issue — [godotengine/godot#93508 (SharedArrayBuffer with thread support disabled)](https://github.com/godotengine/godot/issues/93508)
* Rafael Epplée — [Deploying Godot 4 HTML exports with cross-origin isolation](https://www.rafa.ee/articles/deploying-godot-4-html-exports/)
* GamineAI — [Godot Web export SharedArrayBuffer / COOP-COEP fix](https://gamineai.com/help/godot-web-export-sharedarraybuffer-coop-coep-hosting-fix)
* [`nisovin/godot-coi-serviceworker`](https://github.com/nisovin/godot-coi-serviceworker)
* [`abarichello/godot-ci`](https://github.com/abarichello/godot-ci) · [Marketplace](https://github.com/marketplace/actions/godot-ci)
* Simon Dalvai — [Upload a Godot HTML5 game to itch.io with GitHub Actions](https://simondalvai.org/blog/godot-itchio-upload/)
* Vojtěch Struhár — [Publish your Godot game to itch.io with GitHub Actions](https://www.vojtechstruhar.com/blog/022-godot-itch-github-action/)
* Code My Road — [Tetris AI – The (Near) Perfect Player](https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/)
* Thawsitt Naing — [Tetris AI (Stanford CS221 paper, PDF)](https://thawsitt.me/files/Tetris_AI_CS221_final_paper.pdf)
* [`CamGomezDev/SmartTetris`](https://github.com/CamGomezDev/SmartTetris)
