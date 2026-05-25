# Issue #1 — collected data

* **Repository:** `Jhon-Crow/candy-crush-tetris-godot-game`
* **Issue:** [#1 "init"](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/1)
* **Author:** Jhon-Crow
* **State at analysis time:** open, no labels, no prior comments
* **Pull request:** [#2](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/pull/2)
* **Starting point:** empty repository (`README.md` stub + auto‑generated `.gitkeep`)

## Original text (Russian)

> кэндикраш + тетрис
>
> рандомные шарики в фигурах, можно включить автоматическое управление падением фигур
>
> сделай самую примитивную реализацию этой игры:
> тетрисные фигурки из из разноцветных шариков падают (пока без управления)
> важно - хоть игра и происходит в 2д пространстве использую 3д сцену чтоб легче было потом прорабатывать визуал.
> сделай всё на godot и экспортируй как html5 (если можно в гитхаб pages), в идеале добавь ci cd для автоматической загрузки на itchio с инструкцией, как подключить репозеторий к своему itchio
> в комментариях оставь скриншоты.
>
> Please collect data related about the issue to this repository, make sure we compile that data to `./docs/case-studies/issue-{id}` folder, and use it to do deep case study analysis (also make sure to search online for additional facts and data), and propose possible solutions (including known existing components/libraries, that solve similar problem or can help in solutions).
> и реализуй

## English translation

> candy crush + tetris
>
> random balls inside the figures, you can enable automatic control of the falling figures
>
> make the most primitive implementation of this game:
> tetris figures made of multicoloured balls fall (for now without control)
> important — although the game happens in 2D space, use a 3D scene so the visuals
> are easier to work on later.
> do everything in Godot and export as HTML5 (to GitHub Pages if possible); ideally
> add CI/CD for automatic upload to itch.io with instructions on how to connect the
> repository to your itch.io.
> leave screenshots in the comments.
>
> (research/case‑study request) … and implement.

## Extracted requirements

| # | Requirement | Priority | Where addressed |
|---|---|---|---|
| R1 | Tetris pieces made of multicoloured balls | must | `scripts/Game.gd` (`SHAPES`, `COLORS`, `_make_ball`) |
| R2 | Pieces fall automatically (no player control) | must | `_process` / `_step` fall loop |
| R3 | "Candy Crush" flavour (colourful candy balls) + line clearing | must | glossy candy materials + `_clear_full_rows` |
| R4 | Optional **automatic control** of the falling figures | should | `auto_play` heuristic (`_best_target_column`) |
| R5 | Built in **Godot** | must | Godot 4.5 project |
| R6 | 2D gameplay rendered in a **3D scene** | must | `Node3D`, sphere meshes, ortho camera, lights/shadows |
| R7 | Export to **HTML5/Web** | must | `export_presets.cfg` Web preset |
| R8 | Deploy to **GitHub Pages** | should | `.github/workflows/deploy.yml` |
| R9 | **CI/CD to itch.io** + connection instructions | should | `deploy.yml` `publish-itch` job + README |
| R10 | **Screenshots** in comments | must | posted to issue/PR + `docs/screenshots/` |
| R11 | **Case study** in `docs/case-studies/issue-1/` | must | this folder |
