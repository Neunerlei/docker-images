# Proposal: Test suite for the entrypoint/images

**Status: PROPOSAL — nothing implemented yet.** Branch `feature/basic-auth`, 2026-11-12.
Nothing in this document is wired into the repo yet; it exists to align us before we build.

## The problem

`feature/basic-auth` grew beyond basic auth: read-only filesystem support, the
`legacy.d/` framework with 4 compatibility layers, work-data sync, the argv fix,
DNS resolver autodetection — ~55 files, ~1900 insertions. Every additional legacy
case makes "does everything still work?" harder to answer by hand, and the legacy
fallbacks carry a promise we can currently only verify manually: *behave exactly
like `main` did*.

There is no test infrastructure at all today. CI (`.github/workflows/*.yml`) only
builds and publishes images.

The good news: the architecture is unusually testable.

- `util.d/` and `legacy.d/` files are **functions-only, nothing executes at
  source time** — they can be sourced and called directly.
- The entrypoint `exec`s any command after the steps — so
  `docker run --rm <image> nginx -T` renders the full config and dumps it,
  then exits. The image is a test harness for itself.
- Boot behavior is driven entirely by env vars + mounts — a test matrix is just
  data.

## Proposed shape: three tiers

### Tier 1 — Shell unit tests (`bats-core`)

Fast, no Docker build, run per-push. Source the real files, call the real
functions:

| Target | Example assertions |
|---|---|
| `legacy_apply_single_string_command_fallback` | `("npm run dev")` → `("npm" "run" "dev")` + deprecation warning on stderr; embedded quotes stay **literal** (documented old behavior); multi-arg commands and single executables pass through untouched |
| `legacy_bridge_var_www_dotfiles` | dotfiles in `/var/www` get symlinked into the new home; stale bridge links (source gone) are removed; pre-existing entries are never overwritten |
| `write_basic_auth_file` | apr1 hashes round-trip via `openssl passwd`; multi-user `NGINX_BASIC_AUTH_1..n`; realm override; malformed value aborts boot |
| file-marker DSL | `prod-or-env-staging`, `mode-*`, `https`, `-or-` grouping, AND across `.` groups |
| `sync-work-data` / `ensure_user_owned_dir` | staging ↔ work semantics, read-only mount warnings instead of failures |
| legacy expiry | parse `until:` dates from `legacy.d/*.sh` headers and fail once a layer is past its date — today expiry is only tracked in a docs table; a test makes it un-missable |

Environment: functions need `findmnt`, `openssl`, bash ≥ 4 — so bats runs inside
a container (`debian:bookworm` with bats installed, or the built image itself,
which guarantees the production deps). Either way it is a one-liner in CI.

### Tier 2 — Golden-file render tests (the regression guard)

The entrypoint's core behavior is a pure function: **env + mounts → rendered
config**. We make that literal:

1. A `capture` script builds an image from **any git ref**, boots it per scenario
   with `docker run --rm <image> nginx -T`, and saves the dumped, fully expanded
   config (all includes resolved — one deterministic document per scenario).
2. The baseline for **legacy scenarios** (old-style single-string commands, no
   new env vars, writable fs) is captured **from `main`**.
3. Goldens are committed under `tests/golden/`. The test builds the branch
   image, re-captures, and `diff`s.
4. The first diff run will show the intentional changes (resolver snippet,
   `childlogdir` → `/run`, basic-auth includes). We review that diff **once**,
   bless it into the goldens, and re-freeze.

From then on: legacy scenarios must stay **byte-identical to what `main`
produced** — not to re-derived assertions, but to the actual bytes. That is the
strongest honest form of "the fallback works exactly as before". Every future
change to rendered output becomes a reviewed diff instead of silent drift.

**Normalization (important):** a few values in rendered output are legitimately
volatile and get normalized before diffing — the auto-detected resolver IP
(Docker's embedded DNS `127.0.0.11` differs under podman/k8s), self-signed
certificate material, timestamps. A small `sed` pass in the capture script,
explicitly listed, so we normalize *nothing* in secret.

### Tier 3 — Runtime integration scenarios

Data-driven scenario directories — this is what makes the "one or two more
features on the horizon" cheap to cover: a new feature adds a folder, not
framework work.

```
tests/integration/scenarios/
  basic-auth-global/              # 401 without creds, 200 with, wrong password → 401
  basic-auth-per-proxy-override/  # per-proxy realm/users replace global for that location
  legacy-single-string-command/   # boots, serves, stderr contains the deprecation warning
  legacy-dotfile-bridge/          # mounted .npmrc/.composer in /var/www is still read
  readonly-filesystem/            # docker run --read-only boots and serves
  worker-mode/                    # PHP_WORKER_COMMAND path: no web server, worker runs
  https-direct/                   # 80 → 443 redirect; self-signed fallback in dev
  path-composition/               # PROJECT_PATH + SERVICE_PATH → ABS_PATH visible to app
```

Runner: thin bash — `docker run -d`, poll readiness, `curl` assertions, always
`docker rm`. Deliberately **no framework** (no testcontainers, no
container-structure-test): the repo is bash + docker end to end, and a framework
buys parallelism and pretty reports at the price of a second thing to maintain.
If the suite grows to dozens of scenarios we can reconsider.

## CI wiring

New `.github/workflows/tests.yml`, strictly separate from the publish pipelines:

- **Every push:** Tier 1 + Tier 2. Builds 2 images locally (nginx/1.29 +
  php-nginx/8.2 — common engine + one image overlay), amd64 only, no registry
  push. Target: a few minutes.
- **Every PR:** add Tier 3 core scenarios + node-nginx/24 and python-nginx/3.13
  images (image-specific steps: node runtime, gunicorn).
- Legacy `php/` image: smoke on publish pipeline only (deprecated anyway).
- Remember the build-context requirement: `--build-context common=../../_common`.

## Image coverage rationale

| Image | Why |
|---|---|
| nginx/1.29 | proxy mode + per-proxy basic auth + static mode — the auth matrix lives here |
| php-nginx/8.2 | web/worker/build modes, php-specific overlay steps |
| node-nginx/24 | node runtime step, `.npmrc` dotfile bridge |
| python-nginx/3.13 | gunicorn config path |
| php (legacy) | deprecated — smoke only |

## Working procedure this buys us

New legacy case lands → add scenario dir → capture golden from `main` **before**
implementing → implement → diff must be empty (or a reviewed, intentional
change). A regression is a red test with a readable diff, not a broken
deployment.

## Cost

Rough estimate: the harness (capture script, bats setup, runner, CI workflow) is
a day or two; the initial scenario set + main-baseline capture another day,
mostly spent reviewing the first intentional diff. After that, a scenario costs
minutes.

If we need to cut scope: Tier 2 alone answers the stated goal (legacy parity +
regression guard). Tier 1 is cheap and high-leverage. Tier 3 is the most
expensive per assertion — start with the auth matrix and read-only boot only.

## Open questions (for discussion)

1. Image matrix per pipeline — is push+PR split as proposed OK, or all images on PRs?
2. Golden storage: one golden per scenario per image, or only per "engine
   variant" (common vs php-nginx overlay) where output is identical?
3. Bats vs. plain `assert` helper functions in bash (bats adds a dependency but
   pays for itself in assertion readability)?
4. Do we also golden **supervisord** config or is nginx enough for now?
5. Where do the tests live: top-level `tests/` (proposal) vs
   `src/_common/v1/tests/` shipped inside images (rejected here — tests are repo
   concern, not image content, but worth a second opinion)?
