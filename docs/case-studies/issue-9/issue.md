# Issue #9 — добавить прогрессию (Add progression)

## Original text (Russian)

> добавить счётчик счёта, комбо и другие характерные для кенди краш элементы прогрессии.
> возможно визуальные эффекты, ускорения (раш секции), прогрессбар который показывает как скоро раш и тп.
> и реализуй

## Translation (English)

> Add a score counter, combo, and other progression elements characteristic of Candy Crush.
> Possibly visual effects, speed-ups (rush sections), a progress bar showing how soon the rush is, etc.
> And implement it.

---

## Extracted requirements

| ID  | Requirement                                              | Source              | Priority |
|-----|----------------------------------------------------------|---------------------|----------|
| R1  | **Score counter** — track points accumulated over time   | Issue body          | Must     |
| R2  | **Combo system** — detect and reward consecutive clears  | Issue body          | Must     |
| R3  | **Rush sections** — speed-up mechanic like Candy Crush   | Issue body          | Should   |
| R4  | **Progress bar** — show how close rush is to triggering  | Issue body          | Should   |
| R5  | **Visual effects** — feedback on clears, combo, rush     | Issue body          | Could    |
| R6  | **HUD update** — display all new stats on screen         | Implied by R1–R4    | Must     |
| R7  | Continue working as a headless, auto-playing demo        | Existing constraint | Must     |
| R8  | Case study compiled in `docs/case-studies/issue-9/`      | Issue boilerplate   | Must     |
