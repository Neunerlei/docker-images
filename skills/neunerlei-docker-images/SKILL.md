---
name: neunerlei-docker-images
description: Neunerlei docker image family (nginx, node-nginx, php-nginx, python-nginx, legacy php) — self-configuring service containers driven by environment variables and a filename-marker DSL. Use when configuring these images in docker-compose/Dockerfiles, working with /container/custom mounts, templates or env vars, debugging a running container, or when modifying/adding images in the docker-images repo.
---

# Neunerlei Docker Images

Self-configuring "service-in-a-box" containers: NGINX plus a runtime (PHP-FPM, Node.js, Gunicorn, or none), managed by Supervisor. Smart entrypoint reads env vars at startup, renders config templates, starts services. One image covers dev/prod, web/worker/build — reconfigure by env, not rebuild.

## Image index

| Image | Runtime | Modes | Reference |
|---|---|---|---|
| `neunerlei/nginx` | standalone NGINX | `proxy`, `static` | [references/nginx.md](references/nginx.md) |
| `neunerlei/node-nginx` | Node.js | `web`, `worker`, `build` | [references/node-nginx.md](references/node-nginx.md) |
| `neunerlei/php-nginx` (PHP ≥ 8.2) | PHP-FPM | `web`, `worker`, `build` | [references/php-nginx.md](references/php-nginx.md) |
| `neunerlei/python-nginx` | Gunicorn (WSGI) | `web`, `worker`, `build` | [references/python-nginx.md](references/python-nginx.md) |
| `neunerlei/php` (legacy, ≤ 8.4, deprecated) | PHP-FPM only | — | [references/php-legacy.md](references/php-legacy.md) |

Tag lists: `https://docker.neunerlei.eu/neunerlei-<image>-tags.html` (e.g. `neunerlei-php-nginx-tags.html`).

Read the matching reference for exact env vars, defaults, and image-specific dirs — they differ per image. Everything below applies to all images.

Human-facing docs mirror this skill: `docs/common.md` (shared concepts) + `docs/<image>.md` (quick starts, complete ENV tables, per-image examples). When image behavior changes, update both the docs and this skill.

## Entrypoint model

`/container/entrypoint/entrypoint.sh` is a dumb orchestrator: sources `util.d/`, runs `step.d/` scripts in numeric order, then `exec`s the command. Steps build on each other:

```
005-init-custom-on-dev   017-custom-env        040-supervisor      070-user-permissions
010-fail-on-legacy-mounts 020-nginx           050-export-vars    080-custom (hooks)
015-image-vars (image)   030-git               060-user-setup     090-export-custom-vars → 100-execute-command
```

`CONTAINER_MODE` (read-only, exported for templates) is derived:
- `<RUNTIME>_WORKER_COMMAND` set (e.g. `PHP_WORKER_COMMAND`) → `worker`: web server disabled, Supervisor runs your command.
- Entrypoint invoked in a Dockerfile `RUN` without a command → `build` (see [Build mode](#build-mode-multi-stage-builds)).
- Otherwise → `web` (nginx image: any `PROXY_*_CONTAINER` → `proxy`, else `static`).

`mode-*` filename markers match against `CONTAINER_MODE`.

## ENVIRONMENT switch

`ENVIRONMENT` = `production` (default) | `development`/`dev`. Any value other than `development`/`dev` counts as production. Drives NGINX tuning, error pages, scaffolding. Framework-standard vars derive from it per image (`NODE_ENV`, `APP_ENV`/`APP_DEBUG`, `FLASK_ENV` — see references). Explicit values always win, so `ENVIRONMENT=production` + `APP_ENV=staging` is valid: prod-tuned container, staging app config.

Dev-only: with `ENVIRONMENT=development` and `/container/custom` mounted, step 005 scaffolds the full custom directory structure as a discoverable guide.

## Shared environment variables

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `33` / `33` | Run processes as www-data with this uid/gid — match host file permissions. |
| `ENVIRONMENT` | `production` | See above. |
| `CONTAINER_MODE` | (derived) | Read-only; see Entrypoint model. |
| `MAX_UPLOAD_SIZE` | `100M` | Sets all upload-related limits at once. Read-only byte form: `MAX_UPLOAD_SIZE_BYTES`. |
| `DOCKER_PROJECT_HOST` | `localhost` | Public hostname, for app URL generation. |
| `DOCKER_PROJECT_PATH` | `/` | Public base path of the whole project group. |
| `DOCKER_PROJECT_PROTOCOL` | `http` | Public protocol; `https` switches NGINX to SSL listen + HTTP→HTTPS redirect. |
| `DOCKER_SERVICE_PROTOCOL` | = project protocol | Protocol an outer proxy uses to talk to THIS container. |
| `DOCKER_SERVICE_PATH` | `/` | This service's sub-path within the project. |
| `DOCKER_SERVICE_ABS_PATH` | (derived) | Read-only `PROJECT_PATH` + `SERVICE_PATH`; apps use it for absolute URLs. |
| `NGINX_DOC_ROOT` | `/var/www/html/public` | Static document root. |
| `NGINX_CLIENT_MAX_BODY_SIZE` | = `MAX_UPLOAD_SIZE` | Override only with a specific need. |
| `NGINX_CERT_PATH` / `NGINX_KEY_PATH` | `/etc/ssl/certs/custom/{cert,key}.pem` | Cert paths when serving HTTPS directly. |
| `NGINX_PROXY_CONNECT_TIMEOUT` | `5s` | Backend connect timeout (php-nginx: `fastcgi_connect_timeout`). |
| `NGINX_PROXY_READ_TIMEOUT` | `60s` | Response read timeout (php-nginx: `fastcgi_send_timeout`). |
| `NGINX_PROXY_SEND_TIMEOUT` | `60s` | Request send timeout (php-nginx: `fastcgi_read_timeout`). |
| `NGINX_KEEPALIVE_TIMEOUT` | (calculated) | Derived from the other timeouts if unset. |
| `NGINX_RESOLVER` | auto-detected | DNS servers for dynamic upstream names (see [NGINX DNS resolution](#nginx-dns-resolution)); detected from `/etc/resolv.conf` each boot, fallback `127.0.0.11`. Space-separated list = multiple servers. |
| `NGINX_RESOLVER_VALID_TIMEOUT` | `30s` | `valid=` cache TTL for resolved addresses. |
| `NGINX_RESOLVER_TIMEOUT` | `5s` | DNS query timeout (`resolver_timeout`). |
| `NGINX_TRY_FILES` | per image | Root-location routing; see references. |
| `NGINX_BASIC_AUTH` | (disabled) | Basic auth for the whole server: `username clear-password`; extra users `NGINX_BASIC_AUTH_1..n`, realm `NGINX_BASIC_AUTH_REALM`. Per-proxy: `PROXY_<KEY>_BASIC_AUTH(_1..n/_REALM)` replaces it for that location. Directives are generated as snippets (`/etc/nginx/snippets/basicAuth.nginx.conf` server-wide, `proxy.d/<key>.auth.conf` per service — always present, empty when disabled); passwords hashed with `openssl passwd -apr1`; malformed values abort boot. |
| `USER_OWNED_DIRECTORIES` | (none) | Space-separated extra dirs to create/own as www-data at boot (volumes the app writes into). Image-level dirs are declared at build via the installer's `--user-owned-dir` flag. |
| `CONTAINER_WWW_DATA_HOME_DIR` | `/container/work/www-data-home` | Read-only constant: writable home of every www-data process (supervisor `user=` programs need `environment=HOME="${CONTAINER_WWW_DATA_HOME_DIR}"`; gosu and php-fpm workers derive it from the passwd entry). Lives in the work dir → writable on read-only filesystems; not reset per boot. Legacy `/var/www` dotfiles are bridged in as symlinks with a deprecation warning. Don't bake build-time content into `$HOME` (tmpfs hides it; named volumes go stale) — use `PLAYWRIGHT_BROWSERS_PATH`/`COMPOSER_HOME`/etc. |

Rule of thumb: use `MAX_UPLOAD_SIZE` and only override individual limits when values must differ.

## Path composition

Multiple services behind one reverse proxy compose their public URL from:
- `DOCKER_PROJECT_PATH` — base path of the service group (`/myapp/`)
- `DOCKER_SERVICE_PATH` — this service's sub-path (`/api/`)
- `DOCKER_SERVICE_ABS_PATH` (read-only) — both combined

Outer proxy routes on `SERVICE_PATH`; application code generates links with `SERVICE_ABS_PATH`. Example: project at `/project-alpha`, API at `/api` → `DOCKER_PROJECT_PATH=/project-alpha`, `DOCKER_SERVICE_PATH=/api` → `ABS_PATH=/project-alpha/api/`.

## HTTPS / SSL termination

- **Direct HTTPS:** `DOCKER_PROJECT_PROTOCOL=https` → NGINX listens on 443, redirects 80→443. Mount certs to `/container/custom/certs/{cert,key}.pem`. Without certs, self-signed ones are generated (warning printed; dev only).
- **Terminated at outer gateway (recommended):** `DOCKER_PROJECT_PROTOCOL=https` + `DOCKER_SERVICE_PROTOCOL=http` → container speaks plain HTTP internally but knows the public side is secure.
- App code should trust `X-Forwarded-Proto`, not the internal listen port.

## NGINX DNS resolution

NGINX resolves dynamic upstream names — a variable in `proxy_pass` (`proxy_pass http://$backend;`), `server … resolve` — on every request via its `resolver` directive; it never consults `/etc/resolv.conf` for those. The entrypoint therefore detects the servers from `/etc/resolv.conf` on every boot, so one image works everywhere: Docker user-defined networks → embedded DNS `127.0.0.11`, Kubernetes → cluster DNS, Podman/host networking → runtime or host resolvers (fallback: `127.0.0.11`). Override with `NGINX_RESOLVER`.

Kubernetes caveat: the resolver ignores `search`/`ndots` from `/etc/resolv.conf` — use FQDNs (`service.namespace.svc.cluster.local`) for variable-based upstreams; short names like `my-service` will not resolve.

## The /container/custom mount

Single mount point for ALL customization, usually `./docker/custom:/container/custom`. Read-only mounts (Kubernetes config maps) are fully supported — the entrypoint only reads from it, rendered copies land in the work dir, and it never chowns the mounted files:

```
custom/
├── env/            # *.env / *.env.sh variable declarations (loaded before services)
├── nginx/          # server-level snippets → /etc/nginx/snippets/…
│   ├── global/     # http-level snippets
│   ├── location/   # root-location snippets (web/static mode)
│   └── proxy/      # nginx image only: per-service snippets in proxy mode
├── certs/          # cert.pem + key.pem
├── entrypoint/     # startup hook scripts
└── <runtime>/      # image-specific (php/, php/fpm/ …) — see references
```

Legacy mounts (`/etc/ssl/certs`, `/etc/container/templates/.../custom`) abort startup (step 010) with migration instructions. Migration guide: `docs/migration/2026-02-05-migrate-to-centralized-container-dir.md`.

## Read-only filesystems

`readOnlyRootFilesystem: true` (Kubernetes) and `docker run --read-only` are fully supported. Everything written at runtime goes to two places:

1. `/container/work` — all rendered configuration. May start **empty** (tmpfs, `emptyDir`): the entrypoint seeds it on every boot from the image's pristine build state (`/container/work-data-staging`) and resets it on every restart, so stale config from a previous boot is discarded. Mount it writable.
2. Runtime dirs as tmpfs: `/run`, `/tmp`, `/var/lib/nginx`, `/var/log/nginx`.

```bash
docker run --read-only \
  --tmpfs /run --tmpfs /tmp --tmpfs /var/lib/nginx --tmpfs /var/log/nginx \
  -v my-work:/container/work \
  my-image
```

## Filename markers (DSL)

Loading conditions live in filenames — behavior visible at a glance. Applies to custom snippets, env files, entrypoint hooks and internal templates. NOT to core template overrides.

- `.` splits AND groups: every group containing a known marker must be satisfied. Non-marker groups (`.conf`, `.ini`, `.sh`) are ignored.
- `-or-` splits OR clauses within one group; one true clause satisfies the group.

| Marker | Condition | Example |
|---|---|---|
| `prod` / `dev` | `ENVIRONMENT` is production / development | `10-security.prod.conf` |
| `env-*` | `ENVIRONMENT` matches suffix; `env-prod`/`env-dev` alias production/development; custom values (`env-staging`) work | `30-analytics.prod-or-env-staging.conf` |
| `mode-*` | `CONTAINER_MODE` matches suffix | `02-clear-cache.mode-web.sh` |
| `https` | `DOCKER_SERVICE_PROTOCOL=https` | `03-websockets.https.conf` |
| `feat-*` | Feature present in `feature_registry` (mostly internal) | `nginx.service.feat-nginx.conf` |

`20-hsts.prod.https.conf` = production AND https. New markers: define `_file_marker_is_*()` (zero args = scalar, one arg = wildcard suffix) and register in `file_marker_condition_registry`.

## Templating

Every config file — built-in templates in `/container/templates/` AND custom files in `/container/custom/` — is rendered with `${VAR}` substitution from exported env (bash parameter expansion, no external engine). Add `[[DEBUG_VARS]]` on its own line anywhere in a file → entrypoint prints all substitutable vars and exits. Not available in entrypoint hooks (use `printenv | sort` there).

Note: `get_all_vars()` filters out bash internals, system vars, and anything starting lowercase or `_` — name template vars UPPERCASE.

## Custom env files (`custom/env/`)

The single place for project-level derived/dynamic variables, instead of scattering them across Dockerfile `ENV`, Compose `environment:`, and `-e` flags. Loaded by step 017 — before any service configuration.

- `*.env` — plain `KEY=VALUE`; auto-exported; `${VAR}` references expand at source time.
- `*.env.sh` — real shell for dynamic lookups; MUST `export` explicitly (`set -a` is not active).
- Order: all `.env` alphabetically, then all `.env.sh` alphabetically. Numeric prefixes control order. Markers apply.

```dotenv
# 10-routing.env
APP_URL=${APP_PROTOCOL}://${APP_HOST}
# 10-routing.prod.env → production-only extension/override
```

```bash
# 20-dynamic.env.sh
export CACHE_TTL=$(redis-cli get cache_ttl 2>/dev/null || echo "3600")
```

## Entrypoint hooks (`custom/entrypoint/`)

`.sh` scripts run during startup, before `supervisord`; full env available. Markers apply (`01-migrations.mode-build.sh`). Plain scripts, not templates.

## Core template overrides (advanced)

Mount a file at the exact path of a default template (e.g. `/container/templates/nginx/nginx.conf`) to replace it wholesale. All-or-nothing; markers do NOT apply.

## Supervisor & fatal failures

All services run under Supervisor. Apply changed configs without a container restart:

```bash
docker exec my-container reload-supervisor   # supervisorctl restart all
```

A process failing to start 3 times in quick succession is marked `FATAL`. A Supervisor eventlistener then exits the whole container — a dead worker can never hide inside a healthy-looking container. Combine with `restart: unless-stopped` for self-healing; in dev (no restart policy) the visible stop surfaces the failure immediately.

Graceful worker shutdown: `*_WORKER_STOP_WAIT_SECS` only takes effect if Docker waits longer than it. Raise `stop_grace_period` above it:

```yaml
stop_grace_period: 120s
environment:
  - PHP_WORKER_COMMAND=php /var/www/html/artisan queue:work
  - PHP_WORKER_STOP_WAIT_SECS=90
```

## Bash wrapper (env in `docker exec`)

Entrypoint-exported vars are normally invisible to `docker exec` sessions. Build moves `/bin/bash` → `/bin/_bash` and installs a wrapper that sources `/container/work/container-vars.sh` first (`/bin/sh` symlinks to it too). Result: `docker exec my-container bash` sees `DOCKER_SERVICE_ABS_PATH` etc. Other shells (zsh) must source that file in their rc. Runtime CLIs are env-wrapped the same way (`php`; `python`/`pip`; `node` — see references); prefix `_` accesses originals.

Container values take precedence over inline overrides: the wrapper exports every var unconditionally, so `NODE_ENV=test node --test` or `docker exec -e APP_ENV=testing … php artisan test` run with the container's values. For a one-off override invoke the original binary (`NODE_ENV=test _node --test`); for a permanent change set the var where the container gets its env (compose `environment:` or `custom/env/`).

## Build mode (multi-stage builds)

`RUN /container/entrypoint/entrypoint.sh` with NO command in a Dockerfile → `CONTAINER_MODE=build`: full env setup, services skipped, final `exec` skipped. Later `RUN` commands see the exact variables production will have — same paths, same derived values.

```dockerfile
FROM neunerlei/php-nginx:latest AS builder
ARG DOCKER_PROJECT_PROTOCOL
ENV DOCKER_PROJECT_PROTOCOL=${DOCKER_PROJECT_PROTOCOL}
COPY --chown=www-data:www-data ./src ./src
RUN /container/entrypoint/entrypoint.sh        # set up environment
RUN composer install --no-dev --optimize-autoloader
RUN ./vendor/bin/phpunit

FROM neunerlei/php-nginx:latest
COPY --from=builder /var/www/html ./
```

Hooks can target the build phase only: `01-migrations.mode-build.sh`.

## Utility commands

Anything in `$CONTAINER_BIN_DIR` (`/container/bin`, prepended to `PATH`) is callable as a shell command — works on read-only filesystems, no Dockerfile changes. kebab-case names, no extension. Ships `reload-supervisor`, `supervisor-crash-on-fatal`; images add their own (see references).

## Migration notes (behavior changes)

Breaking or behavior-changing releases are documented in `docs/migration/`, one file per change, prefixed with the release date (`YYYY-MM-DD-…`). Check them when a container behaves differently after a rebuild, since rolling tags pick up changes without an opt-in.

- **2026-11-12 — exact command arguments** (`docs/migration/2026-11-12-exact-command-arguments.md`):
  - Commands keep their exact argument boundaries (`sh -c '…'` works). Passing a command as a **single string** (`command: ["npm run dev"]`, K8s `args: ["php artisan queue:work"]`) still runs but logs a deprecation warning and will fail in a future release. Use separate arguments. `$entrypoint_command` is now an array.
- **2026-11-12 — www-data home directory** (`docs/migration/2026-11-12-www-data-home-directory.md`):
  - The www-data home moved from `/var/www` to `/container/work/www-data-home`. Dotfiles in `/var/www` (`.npmrc`, `.ssh`, `.gitconfig`, …) are bridged in as symlinks with a deprecation warning. The npm and composer caches moved with the home. Don't bake build-time content into `$HOME`. Dev containers now really add `/var/www/html` to git's `safe.directory` (the step never ran before).
- **2026-11-12 — gunicorn stop timeout (python-nginx)** (no separate guide — feature documentation lives in `docs/python-nginx.md`):
  - New `GUNICORN_TIMEOUT`/`GUNICORN_GRACEFUL_TIMEOUT`/`GUNICORN_MAX_REQUESTS(_JITTER)` knobs (opt-in, defaults match gunicorn's own). Supervisor now waits `GUNICORN_GRACEFUL_TIMEOUT + 10` (default 40s) for gunicorn to stop instead of 10s — a behavior change on rolling rebuilds, configurable via `GUNICORN_STOP_WAIT_SECS`. Raise `NGINX_PROXY_READ_TIMEOUT` together with `GUNICORN_TIMEOUT`.
- **2026-02-05 — centralized container dir** (`docs/migration/2026-02-05-migrate-to-centralized-container-dir.md`): all custom mounts go to `/container/custom`. Legacy mount paths abort startup (step 010).

---

# Working in the docker-images repo

## Two layers

- `src/_common/v1/` — shared engine: `installer.sh` + `container/{bin,entrypoint,templates}` copied verbatim into every image. Sacred: change only for features genuinely reusable in ALL images.
- `src/<image>/<version>/` — image-specific: `container/entrypoint/step.d/` (e.g. `015-image-vars.sh`), `container/templates/`, `src/` (default app files like `index.php`), `Dockerfile`.

Image templates with the same relative path override common ones (e.g. `templates/nginx/snippets/root.nginx.conf`).

Env var layering (order matters): framework defaults (`common-env.sh` — must stay dependency-free, runs before every step and in `installer.sh`) → image defaults (`015-image-vars.sh`) → project vars (`custom/env/`, step 017) → shell wrapper.

Registries (declared in `entrypoint.sh`, images append):
- `file_marker_condition_registry` — marker name → condition function
- `feature_registry` — space-separated string; gates whole chunks of step.d logic (`nginx`, `supervisor`); matched by `feat-*` markers
- `user_owned_directories_registry` — dirs chowned to www-data when PUID/PGID change; created if missing

## Dockerfile pattern

```dockerfile
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}
ENV INSTALLER_EXTRA_DEPENDENCIES="..."        # extra apt packages
RUN --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
        --tpl nginx-custom-snippets \
        --source-dir /container/custom/nginx \
        --target-dir /etc/nginx/snippets/custom.d
# --tpl names the snippet mechanism; --source-dir where user snippets land;
# --target-dir where they are rendered to. --remove-dependency drops packages.
COPY container /container
COPY src /var/www/html
```

Build from the `src/` directory so relative paths resolve: `docker build --build-context common=../../_common -f <image>/<ver>/Dockerfile -t my-tag .`

Naming: steps `NNN-descriptive-name.sh` (leave 5–10 gaps for insertions), marker functions `_file_marker_is_*` / `_file_marker_has_*`, templates carry their conditions in-filename. Keep installer layers before `COPY` for cache hits — `_common` changes invalidate the bind-mount layers.

## Automated builds

`.github/workflows/<image>.yml` is config only; the engine lives in `.github/.release/`:

1. **discover** — paginated Docker Hub tag fetch for the base image, semver filtering, version matrix; cascading source selection: `1.29.1` falls back `1.29.1` → `1.29` → `1.28` → … until a source dir exists (new patch/minor versions build without changes).
2. **build-and-attest** — parallel matrix, multi-platform (`linux/amd64`, `linux/arm64`) via the `SOURCE_IMAGE` build arg; pushes SLSA build-provenance attestations.
3. **publish-tag-list** — generates the tag-overview HTML pages deployed to GitHub Pages (the `docker.neunerlei.eu` links above).
