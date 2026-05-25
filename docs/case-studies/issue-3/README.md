# Case study — issue #3: fix itchio deploy

A root-cause analysis of the failed itch.io publish job reported in
[issue #3](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/3).

Supporting material: [`issue.md`](issue.md) (raw issue text + requirements) and
[`research.md`](research.md) (sourced external facts and timeline).

---

## 1. What was reported

The author reported that the **"Build & Deploy"** GitHub Actions workflow was
failing and linked to a specific step in run
[`26419727023`](https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/actions/runs/26419727023/job/77771850032#step:3:12).

The repository already had the required secrets and variables configured:

- **Secret:** `BUTLER_API_KEY` — itch.io API key for `butler`
- **Variables:** `ITCH_USER`, `ITCH_GAME` — itch.io username and game slug

---

## 2. Root cause analysis

### 2.1 Failed step

The failure occurred in the `Publish to itch.io` job, at the **"Install butler"**
step (step 3, line 12):

```yaml
- name: Install butler
  run: |
    set -euo pipefail
    curl -sL -o butler.zip https://broth.itch.ovh/butler/linux-amd64/LATEST/archive/default
    unzip -q butler.zip
    chmod +x butler
    ./butler -V
```

**Error from CI log:**
```
##[error]Process completed with exit code 6.
```

### 2.2 curl exit code 6

From the curl documentation:

> **Exit code 6** — *Couldn't resolve host.* The given remote host's address was not resolved.

This means `curl` was completely unable to resolve the DNS name `broth.itch.ovh`.

### 2.3 Domain decommissioning

The domain `broth.itch.ovh` has been **permanently decommissioned** by itch.io.
The service was migrated to `broth.itch.zone`.

Verified locally:
```
$ curl -sI https://broth.itch.ovh/butler/linux-amd64/LATEST/archive/default
# → (no output; connection failed)

$ curl -sI https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
# → HTTP/2 307 redirect to Cloudflare R2 storage (success)
```

### 2.4 Timeline of events

```
t=0   PR #2 merged → initial deploy.yml ships with:
        URL: https://broth.itch.ovh/...   ← broken domain
        Secret: BUTLER_CREDENTIALS        ← wrong name
      Publish-itch job was SKIPPED because ITCH_USER/ITCH_GAME vars were not set.
      The broken URL went unnoticed.

t=1   Commit a246267 ("fix deploy.yml env var name"):
        Fixes: BUTLER_CREDENTIALS → BUTLER_API_KEY (correct secret name)
        ITCH_USER and ITCH_GAME are now configured → job no longer skipped.
        Dead domain URL remains unchanged.

t=2   Run 26419727023 triggered by a246267.
        "Install butler" step runs for the first time.
        curl fails to resolve broth.itch.ovh → exit code 6 → job FAILURE.

t=3   Issue #3 opened pointing to the failing step.
```

### 2.5 Why the broken URL was not caught earlier

The `publish-itch` job has a guard condition:

```yaml
if: github.ref == 'refs/heads/main' && vars.ITCH_USER != '' && vars.ITCH_GAME != ''
```

Before the `ITCH_USER` and `ITCH_GAME` repository variables were set, this job
was silently skipped on every run. The dead URL inside the job body was never
executed. Only after commit `a246267` fixed the secret name and the operator
configured the itch.io variables did the job actually run — and immediately fail.

---

## 3. Solution

Change one line in `.github/workflows/deploy.yml`:

```diff
- curl -sL -o butler.zip https://broth.itch.ovh/butler/linux-amd64/LATEST/archive/default
+ curl -sL -o butler.zip https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
```

The new URL `broth.itch.zone` is the current itch.io butler distribution
endpoint and returns `HTTP 307` (redirect to Cloudflare R2 storage).

---

## 4. Options considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Replace `broth.itch.ovh` → `broth.itch.zone` | Minimal, correct, follows itch.io's own migration | None | **Chosen** |
| Pin a specific butler version by release tag | Reproducible builds | Must manually track butler releases | Not needed — LATEST is acceptable |
| Use `josephbmanley/butler-publish-itchio-action` | No URL management | External action dependency, less transparent | Not needed |
| Download butler via the itch app | Works | Not available in headless CI | Rejected |

---

## 5. Verification

After applying the fix, a push to `main` with `ITCH_USER` and `ITCH_GAME`
variables configured should result in:

1. `export-web` job: ✅ Green (was already passing)
2. `deploy-pages` job: ✅ Green (was already passing)
3. `publish-itch` job:
   - "Install butler" step: downloads and prints butler version ✅
   - "Push to itch.io" step: uploads `build/web` to `{ITCH_USER}/{ITCH_GAME}:html5` ✅

---

## 6. Known limitations & future work

| Item | Description |
|------|-------------|
| Butler URL pinning | Using `LATEST` means butler auto-updates, which is generally fine but could cause unexpected breakage if itch.io introduces a breaking change |
| No butler version check | Could add a step that verifies the butler version meets a minimum requirement |
| itch.io outages | If `broth.itch.zone` goes down, the job will fail again — consider caching the butler binary |

---

## 7. References

| Source | URL |
|--------|-----|
| Failed CI run (issue link) | https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/actions/runs/26419727023/job/77771850032#step:3:12 |
| butler on GitHub | https://github.com/itchio/butler |
| broth.itch.zone (working endpoint) | https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default |
| curl exit codes | https://curl.se/docs/manpage.html |
| PR #4 (fix) | https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/pull/4 |
