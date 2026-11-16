# Test suite — implementation plan

**Status: PLAN — ready for implementation.** Branch `feature/basic-auth`, 2026-11-12.

This is the working brief for whoever builds the suite. It refines the team proposal in
[`2026-11-12-test-suite.md`](./2026-11-12-test-suite.md) (read it first — Tier 1/2/3 and most
of its reasoning stand) with the decisions taken since. Where the two documents disagree,
**this one wins**.

The implementation is reviewed at three checkpoints (see [Checkpoints](#checkpoints)). Do not
skip ahead past a checkpoint without the review.

---

## 1. Decisions (what changed vs. the proposal)

1. **Two separate things, not one.**
   - **Phase 1 — one-time parity check (local only).** `main` vs. this branch, using synthetic
     scenarios *and* real consumer Dockerfiles. Its purpose is to answer "does the branch break
     anything that worked on `main`?" exactly once. **Nothing from Phase 1 is committed** — no
     goldens from `main`, no consumer list, no parity scripts in CI.
   - **Phase 2 — the permanent suite.** Its baseline is *the reviewed branch state*, i.e. the
     state `main` will have after the merge. Nothing in the committed suite references `main`
     or a git ref.
2. **Goldens are recorded from the branch**, after Phase 1 has been reviewed and its findings
   fixed. The proposal's "capture from `main`, review the first diff, bless" step *is* Phase 1 —
   it just happens locally and once.
3. **Capture more than `nginx -T`.** The capture covers supervisor config, the exported variable
   snapshot, the `www-data` passwd entry, ownership of user-owned dirs, and (in live mode) the
   environment of the actual service processes. An nginx-only capture would miss exactly the kind
   of regression Phase 1 is meant to find (see the HOME finding in §6).
4. **The capture tooling is image-tag agnostic.** `capture <image-ref> <scenario>` must not know
   which git ref built the image. Phase 1 is then just "run the permanent capture against two
   tags and diff" — and the same trick is reusable for any future large branch.
5. **The legacy `neunerlei/php` images (`src/php/`) are out of scope.** They do not use
   `_common` and this branch does not touch them.

---

## 2. Architecture

Everything lives under top-level `tests/`. Bash end-to-end, plus `bats-core` for the unit tier
(the proposal's reasoning against heavier frameworks stands).

```
tests/
  run.sh                       # entry point: unit | golden [--update] | integration | all
  lib/
    build-image.sh             # build one of our images from a given source tree under a test tag
    probe.sh                   # runs INSIDE the container, prints the observable surface
    capture.sh                 # boots an image for a scenario, collects + normalizes probe output
    normalize.sed              # the ONLY place volatile values get normalized (see §2.4)
    helpers.bash               # shared bats helpers (container lifecycle, http polling, asserts)
  unit/*.bats                  # Tier 1
  scenarios/<name>/            # Tier 2 + Tier 3 scenarios (see §2.3)
  .cache/                      # pinned bats-core, built-image stamps — gitignored
  .parity/                     # Phase 1 workspace — gitignored, never committed
```

### 2.1 Building images (`lib/build-image.sh`)

- Input: image name, version dir, **source tree path** (the repo checkout to build from — this is
  how Phase 1 builds `main` from a `git worktree`), source image tag, output tag.
- Use the same `docker build` invocation as `.github/.release/local-build.js`
  (`--build-context common=<tree>/src/_common`, `--build-arg SOURCE_IMAGE=…`). Call `docker build`
  directly rather than `bin/build.sh`: the latter resolves versions via Docker Hub and tags
  as `neunerlei/<image>:<tag>`.
- **Never tag test images as `neunerlei/*`.** Local tags shadow the registry — every other
  project on the machine that builds `FROM neunerlei/...` would silently pick up a test build.
  Use `nl-test/<image>:<version>-<label>` (e.g. `nl-test/php-nginx:8.3-main`,
  `nl-test/php-nginx:8.3-branch`).
- Respect the version-directory fallback: e.g. `php-nginx:8.3` and `8.5` build from
  `src/php-nginx/8.2`, `node-nginx:25` from `24`, `python-nginx:3.14` from `3.13`. Resolve the
  directory the same way the release tooling does.
- `run.sh` must accept pre-built tags (e.g. `--image nginx=nl-test/nginx:1.29-branch`) so a
  developer iterating on a test does not rebuild images every run.
- amd64 only.

### 2.2 Probe and capture (`lib/probe.sh`, `lib/capture.sh`)

The probe is **bind-mounted** into the container, never baked in — that is what lets the same
probe run against a `main` image and a branch image. Mount it under a neutral path
(`/nl-test/`); in particular never under one of the paths the legacy mount check aborts on
(`/etc/ssl/certs`, `/etc/container/templates/...`, `/usr/bin/container/custom`).

Two capture modes:

| Mode | How | Captures |
|---|---|---|
| **static** | `docker run --rm … <image> /nl-test/probe.sh static "$@"` — the entrypoint runs all steps, then `exec`s the probe instead of supervisord | entrypoint exit code + stdout/stderr; the argv the command received; `nginx -T`; rendered supervisor config (`/etc/supervisor/…`); rendered image-specific config (gunicorn.conf.py, php ini/pool dirs); the `container-vars.sh` snapshot (sorted); `getent passwd www-data`, `id www-data`; owner/group/mode of the user-owned dirs and of `/container` (`find -printf`); a sorted checksum list of `/container/work/data` |
| **live** | `docker run -d …` with the default command, poll until ready (bounded timeout, no fixed sleeps), then `docker exec … /nl-test/probe.sh live` | everything from static, plus: `supervisorctl status`; per supervised process: user and `HOME` (from `/proc/<pid>/environ` — **except php-fpm**, see below); HTTP status + relevant headers of a few requests (`/`, an auth-protected path where configured) |

Notes:
- **php-fpm environment:** `/proc/<pid>/environ` is an exec-time snapshot and is not reliable
  for FPM workers. Mount a tiny PHP script into the doc root and request it
  (`getenv('HOME')`, `posix_getpwuid(posix_geteuid())`) instead.
- Output format: one file per section in a capture directory (`exit-code`, `stdout`, `stderr`,
  `argv`, `nginx-T.conf`, `supervisor.conf`, `vars.sh`, `passwd`, `ownership.txt`, …). Per-section
  files make diffs readable and let Tier 2 goldens be selective.
- Every container the suite starts gets `--label nl-test=1`, and is removed in a `trap`.
  `run.sh` sweeps leftovers by label at start.

### 2.3 Scenarios (`tests/scenarios/<name>/`)

A scenario is data, not code. Suggested files (all optional except `scenario.conf`):

| File | Purpose |
|---|---|
| `scenario.conf` | images it applies to, capture mode(s), command to pass, `legacy-layer=<file name>` tag if it covers a `legacy.d` layer |
| `env` | `--env-file` for the run |
| `docker-args` | extra `docker run` args (mounts, `--read-only`, `--tmpfs …`) — paths relative to the scenario dir |
| `files/` | content to mount (custom dir contents, dotfiles, …) |
| `Dockerfile` | for **build-time** scenarios (e.g. legacy no-command build mode): `ARG BASE` / `FROM ${BASE}`; the harness builds it on top of the image under test |
| `expect.bats` | Tier 3 assertions (runs against a live container) |
| `golden/<image>/` | Tier 2 captured output (Phase 2 only) |

### 2.4 Normalization (`lib/normalize.sed`)

One explicit, commented list — nothing gets normalized anywhere else. Expected entries:
timestamps (incl. the build-mode marker's "finished at"), container ID/hostname, PIDs, the
auto-detected resolver IP, self-signed certificate material/fingerprints, **salted password
hashes** in generated htpasswd files (the hash differs on every run — normalize it in the golden,
and verify it in Tier 1/3 with `openssl passwd` instead), and ordering of inherently unordered
output (sort env and `find` output before writing).

If something needs normalizing that is not on this list, add it with a comment saying why. Do
not normalize to make a diff disappear.

---

## 3. Phase 1 — one-time parity check (local, not committed)

Work in `tests/.parity/` (gitignored). Reuse `lib/` from §2; the orchestration script for this
phase lives in `.parity/` as well and is thrown away afterwards.

### 3.1 Build

1. `git worktree add tests/.parity/main main` (or any path outside the repo).
2. Build every image/version below **twice** — from the worktree (`-main`) and from the branch
   (`-branch`):

   | Image | Versions needed |
   |---|---|
   | nginx | 1.29, `latest` (→ same as newest tracked) |
   | php-nginx | 8.2, 8.3, 8.5 |
   | node-nginx | 24, 25, `latest` |
   | python-nginx | 3.13, 3.14 |

### 3.2 Synthetic scenarios

Run every scenario from §5 (the Phase 2 list) in static and live mode against both builds and
diff. The legacy ones are what matters most here:

| Legacy layer | Scenario | Expected relation to `main` |
|---|---|---|
| exact-command-arguments | `"echo a  b"`, a multi-line single string, `sh -c 'echo "$X"'`, properly split argv | single-string: same behavior + deprecation warning; `sh -c` was broken on `main` (silent no-op) → **intended** difference |
| build-mode-marker-and-variables | Dockerfile: `RUN /container/entrypoint/entrypoint.sh`, `RUN touch <work data>/x && env > /out`, then boot | later `RUN` sees the same variables as on `main`; image stays bootable; no marker; warning present; changes in the work data survive boot as on `main` |
| www-data-home-directory | `/var/www/.npmrc`, `/var/www/.ssh/config` baked in and mounted | readable as www-data via `~` exactly as on `main` |
| migrate-to-centralized-container-dir | mount `/etc/ssl/certs`, `/usr/bin/container/custom` | exit 1 with the same message; it now aborts earlier, so fewer log lines before the error → **intended** |
| (proxy snippet naming) | custom proxy snippet named `<key>.conf` | still included |

### 3.3 Consumer builds

Build the real consumer Dockerfiles against both builds **without editing them**:

- If the base is a plain `FROM neunerlei/<image>:<tag>`: swap it via a BuildKit named context —
  `docker buildx build --build-context neunerlei/php-nginx:8.3=docker-image://nl-test/php-nginx:8.3-main …`.
  Every `neunerlei/*` ref in the file needs its own `--build-context`.
- If the base comes from a build `ARG` (HAWKI-RAG): override the arg instead.
- Build args/secrets the build needs: use dummy values; don't commit them anywhere.

Then boot each listed target in static and live mode with a minimal env (take it from the
project's compose file / `.env.example`). The apps will not fully work without their databases —
that's fine. We compare the **container-level** surface (§2.2) and whether the supervised
processes start and stay up — not application behavior.

| Consumer | Targets | Base(s) | Watch specifically |
|---|---|---|---|
| `HAWK/HAWKI` | `app_prod`, `app_dev` | `php-nginx:8.3`, `node-nginx:25` | `npm ci` and `composer install` at build time as www-data with the moved HOME; baked `/container/custom`; core template override `/container/templates/nginx/snippets/errors.nginx.conf` still applied next to the changed default snippets |
| `HAWK/HAWKI-RAG` (`docker/python_rag.Dockerfile`) | `bridge-runtime`, `reranker-runtime` (CPU), one worker (`workflow-runtime`) | `python-nginx:3.13` via `PYTHON_NGINX_IMAGE` | **`ENV HOME=/home/rawki`** vs. the forced gunicorn HOME (§6); `PUID=10001` from a custom env file; custom entrypoint script that chowns `/home/rawki`; worker mode via `PYTHON_WORKER_COMMAND` (single string in env — must be unaffected by the argv change) |
| `HAWK/hawki-toolkit-file-converter` | final stage | `python-nginx:3.14` | **`ENV HOME=/tmp`**; own supervisor programs copied into `/container/templates/supervisor/conf.d/`; scripts in `/container/bin/`; postgres + temporal programs come up; `HEALTHCHECK curl /health` |
| `HAWK/futur.move-standalone` | builder + final | `node-nginx:latest`, `nginx:latest` | baked `/container/custom` in both stages; `npm ci` as www-data without build mode |
| `Neunerlei/coach-ai` | builder + final | `node-nginx:24` | **legacy no-command build mode** (`RUN /container/entrypoint/entrypoint.sh`, then `pnpm install`): later `RUN` still gets `NODE_ENV=production`, deprecation warning shown, build succeeds; final stage boots `NODE_WEB_COMMAND` |
| `Neunerlei/doc-lib` | builder + final | `node-nginx:24` | same legacy build-mode pattern as coach-ai |
| `Neunerlei/doc-lib/crawler` | (single stage) | `python-nginx:3.13` | `gosu www-data pip install` at build time; **wholesale override of `/container/templates/python/gunicorn.conf.py`** (the branch changed that template — the new `GUNICORN_*` knobs are inert there, the stopwaitsecs derivation must still render); `CRAWL4_AI_BASE_DIRECTORY=/tmp` workaround |
| `Neunerlei/dantuin-rss-tools-v2` | `app_prod` | `php-nginx:8.5` | `composer install` + `php bin/console cache:warmup` at build time (php is env-wrapped) |

Out of scope (built on the legacy `neunerlei/php:8.4-fpm-alpine`, not affected by this branch):
`HAWK/auth`, `HAWK/futur.move`, `HAWK/hawki-crypto`, `HAWKI/vendor/neunerlei/dbg`.

### 3.4 Expected differences

Keep an explicit allowlist (`.parity/expected-diffs.md`) — one entry per intended change, each
with the commit/migration guide that justifies it. Seed it from the branch's commits and
`docs/migration/2026-11-12-*`, e.g.: the resolver snippet, `childlogdir=/run`, the www-data
passwd home and the new home dir, the deprecation warnings, the gunicorn longevity knobs and
`stopwaitsecs`, the earlier legacy-mount abort, the `sh -c` fix, the new user-owned dirs.

**Anything not on the list is a finding, not a candidate for the list.** Report it; do not
bless it and do not "fix" it by widening normalization.

### 3.5 Output

`tests/.parity/report.md`, one row per (scenario | consumer target) × image:
`identical` / `expected diff (entry #n)` / **`UNEXPECTED`** (with the diff excerpt) /
`build failed on main|branch` (with the log excerpt). That report is what gets reviewed at
checkpoint 2.

---

## 4. Phase 2 — the permanent suite

Starts only after checkpoint 2, i.e. after the findings from Phase 1 are fixed or accepted.

- **Tier 1 — unit (`tests/unit/*.bats`).** The proposal's target table stands. Run bats
  **inside the image under test** (it has `findmnt`, `openssl`, `gosu`, the `www-data` user),
  with a pinned bats-core release from `tests/.cache/` mounted in. One throwaway container per
  run — the functions mutate the filesystem.
- **Tier 2 — goldens.** `run.sh golden --update` records captures from the current tree into
  `scenarios/*/golden/<image>/`; `run.sh golden` re-captures and diffs. Golden changes show up
  in PRs as normal diffs and get reviewed like code. Keep goldens per image (not per "engine
  variant") — the duplication is cheap and the per-image overlays are exactly what can drift.
- **Tier 3 — integration.** `expect.bats` per scenario against a live container. Start with the
  basic-auth matrix and the read-only boot (proposal's cut-scope advice).
- **Legacy layer coverage.** Every file in `legacy.d/` must be referenced by at least one
  scenario's `legacy-layer=` tag. Add a cheap check for that mapping — when a layer is removed,
  its scenarios are removed with it, and a new layer cannot land without one.
- **CI.** New `.github/workflows/tests.yml`, separate from the publish workflows (do not modify
  those). PRs and pushes touching `src/**` or `tests/**`. Build without pushing, amd64, with the
  GitHub Actions build cache. Image split per the proposal unless decided otherwise (§7).
- **Docs.** A "Testing" section in `docs/contributing.md`: how to run, how to add a scenario,
  how to update goldens, the legacy-layer rule. Keep the `skills/neunerlei-docker-images/`
  contributor notes in sync (house rule: docs and skill change together).

## 5. Scenario list

Applies to Phase 1 (both builds) and Phase 2 (goldens from the branch). Image column = minimum
set; the common-layer scenarios run on `nginx` (fastest build), each other image gets a smoke
scenario plus its own specifics.

| Scenario | Images | Tier |
|---|---|---|
| default boot (dev / prod) | all | 2, 3 smoke |
| https direct + self-signed fallback | nginx, php-nginx | 2, 3 |
| proxy mode with several proxies, incl. `<key>.conf` snippet naming | nginx | 2 |
| basic auth global; per proxy; per proxy override; custom snippet already declaring `auth_basic`; malformed value aborts | nginx | 2, 3 |
| read-only filesystem with the documented tmpfs set | all | 3 |
| PUID/PGID change, `USER_OWNED_DIRECTORIES` | nginx, python-nginx | 2 |
| worker mode | php-nginx, python-nginx, node-nginx | 2, 3 |
| `init-build-env` (refuses boot) / `init-build-env --allow-boot` (boots, build-step changes survive) | php-nginx, node-nginx | 3 |
| resolver auto-detection + fallback | nginx | 2 |
| service HOME: gunicorn, php-fpm (PHP probe), wrapped CLIs, `docker exec` shell | python-nginx, php-nginx, node-nginx | 2, 3 |
| the legacy scenarios from §3.2 | nginx (+ node-nginx for build mode) | 2, 3 |

## 6. Known finding to verify first: consumer-set `HOME`

How www-data processes get their `HOME`:

- Everything started via `gosu www-data` (all worker programs, node web, the wrapped CLIs) and
  php-fpm workers take it from the **passwd entry** — gosu overrides an inherited `HOME`
  (verified with gosu 1.17: `docker run -e HOME=/home/rawki … gosu www-data sh -c 'echo $HOME'`
  prints the passwd home). A consumer's `ENV HOME` never reached these, on `main` either.
- The one exception is `[program:gunicorn]`: supervisor's `user=` only switches the uid, so on
  `main` gunicorn inherited supervisord's `HOME` — `/root`, or a consumer's `ENV HOME`. The
  branch pins it via `environment=HOME="${CONTAINER_WWW_DATA_HOME_DIR}"`.

So on `main`, a consumer with `ENV HOME` had gunicorn on that value and all other www-data
processes on `/var/www`; on the branch, all of them use the www-data home. The branch is
*more* consistent — the only behavior change is gunicorn no longer following a consumer's
`ENV HOME`.

Affected consumers: HAWKI-RAG (`HOME=/home/rawki`), file-converter (`HOME=/tmp`). Phase 1 must
confirm the actual `HOME` of gunicorn and of worker-mode processes on both builds and list the
gunicorn change as an expected diff **only** if the maintainer has accepted it (§7).

## 7. Constraints and decisions for the maintainer

Constraints for the implementation:
- Do not change image sources to make them testable. If something cannot be observed without a
  change, stop and flag it.
- Match the repo's bash style (comment density, `[ENTRYPOINT]`-style log prefixes where
  relevant); `shellcheck`-clean (run it from its container image).
- No network in Phase 2 tests beyond image pulls.
- No fixed `sleep`s; poll with timeouts.

Open decisions (not for the implementer):
1. Legacy-expiry check: fail CI past the date (breaks unrelated PRs on that day) or run it as a
   scheduled job? Recommendation: scheduled job.
2. The consumer-`HOME` behavior from §6 — after Phase 1 shows the facts. A global
   `ENV HOME=<www-data home>` in the Dockerfiles was considered and rejected: gosu and php-fpm
   ignore it anyway, and it would move *root's* home into the www-data home (root-owned
   dotfiles there, build-time content baked into a directory that tmpfs/volumes hide at
   runtime, consumer cache mounts at `/root/.cache/...` silently unused).
3. Image matrix per pipeline (proposal: push = nginx + php-nginx, PR = all four).

## Checkpoints

| # | Deliverable | Review focus |
|---|---|---|
| 1 | `lib/` (build, probe, capture, normalize) + `run.sh` skeleton + 2 synthetic scenarios on nginx, captured from both a `main` and a branch build | test tags never `neunerlei/*`; probe mounted not baked; static vs. live correct; normalization list explicit and minimal; cleanup by label works |
| 2 | Phase 1 complete: `.parity/report.md` + `expected-diffs.md` | every `UNEXPECTED` row explained; no allowlist entry without justification; all consumer builds attempted on both sides |
| 3 | Phase 2: goldens from the branch, Tier 1 + Tier 3 starter set, legacy-layer mapping check, `tests.yml`, contributing docs | goldens contain nothing volatile (run twice → no diff); CI is green and does not touch the publish workflows; docs and skill in sync |
