# Issue #3 — fix itchio deploy

**Repository:** [Jhon-Crow/candy-crush-tetris-godot-game](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game)  
**Issue:** [#3 — fix itchio deploy](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/3)  
**Author:** Jhon-Crow  
**State:** Open  
**Date raised:** 2026-05-25  

---

## Original issue body (Russian + context)

> https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/actions/runs/26419727023/job/77771850032#step:3:12
>
> во вкладке secrets - BUTLER_API_KEY  
> в variebles - ITCH_GAME и ITCH_USER
>
> комментарий напиши на русском

**Translation / context:**

The author links to a specific failed CI step (job `77771850032`, step 3, line 12) in run
`26419727023` of the "Build & Deploy" workflow. The notes clarify that the required
credentials/variables are already configured in the repository:

- **Secret:** `BUTLER_API_KEY` (itch.io API key for butler)
- **Variables:** `ITCH_GAME` and `ITCH_USER` (itch.io game slug and username)

The author also requests that the solving comment be written in Russian.

---

## Linked CI run

| Field | Value |
|---|---|
| Run ID | `26419727023` |
| Workflow | Build & Deploy |
| Trigger | Push to `main` (SHA `a2462677251704204dd15f8323d1f6e09101cf59`) |
| Conclusion | **failure** |
| Failed job | Publish to itch.io |
| Failed step | Install butler (step 3) |
| Exit code | `6` |

### Exit code 6

`curl` exit code 6 means: **"Couldn't resolve host."**  
The DNS name `broth.itch.ovh` was unresolvable at the time of the run —
the domain had been decommissioned.

---

## Extracted requirements

| ID | Requirement |
|----|-------------|
| R1 | The itch.io publish job must succeed when `BUTLER_API_KEY`, `ITCH_USER`, and `ITCH_GAME` are set |
| R2 | Butler must be downloaded from a reachable URL |
| R3 | Write a PR/issue comment in Russian explaining the fix |
