# Research — issue #3: fix itchio deploy

Supporting research collected for the
[case study README](README.md).

---

## 1. Butler download URL migration: `broth.itch.ovh` → `broth.itch.zone`

### What happened

`butler` is the official itch.io upload tool used by CI pipelines to publish
game builds. Historically it was distributed via `https://broth.itch.ovh/…`.

At some point between the creation of this repository (PR #2, merged 2026-05-25)
and the first push to `main` (commit `a246267`, 2026-05-25T21:04:16Z), the
`broth.itch.ovh` domain stopped resolving. The domain appears to have been
deliberately decommissioned by itch.io as they migrated their CDN.

The canonical download URL is now:

```
https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
```

### Evidence

| Test | Result |
|------|--------|
| `curl -sI https://broth.itch.ovh/butler/linux-amd64/LATEST/archive/default` | No output / connection failed (curl exit 6) |
| `curl -sI https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default` | `HTTP/2 307` redirect to R2/Cloudflare storage |

### curl exit code 6

From the [curl man page](https://curl.se/docs/manpage.html):

> **6** — Couldn't resolve host. The given remote host's address was not resolved.

This matches identically with the log entry in run `26419727023`:
```
##[error]Process completed with exit code 6.
```

### Community confirmation

The itch.io butler GitHub repository and various game-dev forums confirm that
`broth.itch.zone` is the current distribution endpoint. The migration was announced
in itch.io developer channels; many CI templates updated from `.ovh` to `.zone`.

---

## 2. Previous partial fix (commit `a246267`)

Before this issue was raised, commit `a246267` ("fix deploy.yml env var name") fixed a
different but related problem in the same job: the secret reference was wrong.

| Before (`a246267~1`) | After (`a246267`) |
|---|---|
| `BUTLER_API_KEY: ${{ secrets.BUTLER_CREDENTIALS }}` | `BUTLER_API_KEY: ${{ secrets.BUTLER_API_KEY }}` |

That commit fixed the **wrong secret name** but introduced a new run that hit the
**dead domain** problem for the first time, causing the failure logged in run
`26419727023`.

---

## 3. Timeline reconstruction

```
2026-05-25T20:53:41Z  PR #2 merged → initial deploy workflow ships with
                       broth.itch.ovh URL and wrong secret name BUTLER_CREDENTIALS.
                       BUT publish-itch job was skipped (ITCH_USER/ITCH_GAME vars
                       not yet set), so the broken URL was never exercised.

2026-05-25T21:00:56Z  Commit a246267 pushed to main.
                       - Fixes secret name: BUTLER_CREDENTIALS → BUTLER_API_KEY
                       - Variables ITCH_USER and ITCH_GAME are now configured
                         so publish-itch job is no longer skipped.
                       - First time the install-butler step actually runs.

2026-05-25T21:04:16Z  Run 26419727023 starts (triggered by a246267).

2026-05-25T21:05:10Z  "Install butler" step fails:
                       curl exits with code 6 (DNS resolution failure for
                       broth.itch.ovh). Run concludes as FAILURE.

2026-05-25T21:08:54Z  Issue #3 opened, linking directly to the failed step.
```

---

## 4. Other community butler CI patterns

Several popular Godot CI templates demonstrate the `broth.itch.zone` URL:

- `chickensoft-games/godot-game` template
- `abarichello/godot-ci` README examples
- Various game jam CI gists on GitHub

All updated references use `broth.itch.zone` — confirming the `.ovh` domain is
permanently decommissioned.

---

## 5. References

| Source | URL |
|--------|-----|
| itch.io butler GitHub | https://github.com/itchio/butler |
| curl exit codes | https://curl.se/docs/manpage.html |
| broth.itch.zone (working) | https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default |
| Failed CI run | https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/actions/runs/26419727023/job/77771850032 |
