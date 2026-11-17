# Shared Concepts

Everything in this document applies to **all** images in this repository. The per-image documentation references these sections instead of repeating them:

- [`neunerlei/nginx`](./nginx.md) — standalone reverse proxy / static file server
- [`neunerlei/php-nginx`](./php-nginx.md) — PHP-FPM runtime
- [`neunerlei/node-nginx`](./node-nginx.md) — Node.js runtime
- [`neunerlei/python-nginx`](./python-nginx.md) — Gunicorn (WSGI) runtime

Each image doc keeps its own complete environment variable table and everything image-specific (worker commands, runtime config, snippet types that only exist there).

| I want to… | Read… |
|---|---|
| Understand how the entrypoint configures everything | [The Smart Entrypoint](#the-smart-entrypoint) |
| Know what a mode (`web`, `worker`, `build`, …) means | [Container Modes](#container-modes) |
| Compose public URLs from paths | [Path Composition](#path-composition) |
| Serve HTTPS | [HTTP vs. HTTPS](#http-vs-https) |
| Protect the server with a password | [Basic Authentication](#basic-authentication) |
| Customize anything | [The Custom Directory](#the-custom-directory) and [Customizing the Container](#customizing-the-container) |
| Understand `.prod.` / `.mode-web.` filename suffixes | [Filename Markers](#filename-markers) |
| Use `${VAR}` placeholders in my own files | [Templating](#templating) |
| Run a worker process instead of a web server | [Worker Mode](#worker-mode) |
| Run build steps with the same env as production | [Build Mode](#build-mode) |
| Run with a read-only filesystem / Kubernetes | [Running on a Read-Only Filesystem](#running-on-a-read-only-filesystem) |
| Debug "my variable is empty in `docker exec`" | [The Shell Environment and the Bash Wrapper](#the-shell-environment-and-the-bash-wrapper) |

> **Notation:** headings tagged `MARKER-AWARE` follow the [filename marker](#filename-markers) conditions; headings tagged `TEMPLATES` contain files that are rendered with [`${VAR}` templating](#templating) before they are used.

## The Smart Entrypoint

All images share one entrypoint: `/container/entrypoint/entrypoint.sh`. It is a small orchestrator that sources utility functions, runs the numbered scripts in `/container/entrypoint/step.d/` in order, and finally `exec`s the container command. Each step builds on the previous ones — one step renders all NGINX templates, a later one sets up the runtime user, another runs your custom hooks.

The consequence of that design: **you configure the container with environment variables, not by rebuilding it.** The entrypoint reads the environment on every boot, renders every config file from templates, and starts the services under [Supervisor](#supervisor-and-fatal-failures). A single image therefore covers development and production, web and worker, without a code change — just different variables.

All rendered configuration lives in `/container/work/` (see [Running on a Read-Only Filesystem](#running-on-a-read-only-filesystem) for why that matters).

## Container Modes

`CONTAINER_MODE` is derived by the entrypoint — you never set it directly:

| Mode | When | What happens |
|---|---|---|
| `web` | Default | NGINX serves your app (PHP-FPM / Node / Gunicorn / static files behind it). |
| `worker` | A `<RUNTIME>_WORKER_COMMAND` is set (e.g. `PHP_WORKER_COMMAND`) | The web server is disabled; Supervisor runs your command. See [Worker Mode](#worker-mode). |
| `build` | A `RUN init-build-env` step in a Dockerfile | Full environment setup, services skipped. See [Build Mode](#build-mode). |
| `proxy` / `static` | nginx image only | Any `PROXY_*_CONTAINER` variable present → `proxy`, otherwise `static`. See the [nginx documentation](./nginx.md#proxy-mode-in-depth). |

The mode also drives the filename markers `mode-web`, `mode-worker`, `mode-build`, `mode-proxy` and `mode-static`.

One exception: the nginx image ignores the build mode. Its first configuration step overwrites `CONTAINER_MODE` with `proxy` or `static` before anything else runs — there is no build-time-only configuration for a pure proxy/static image. See [Build Mode](./nginx.md#build-mode) in the nginx documentation.

## The ENVIRONMENT Switch

`ENVIRONMENT` accepts `production` (default), `development` or `dev` — anything that is not `development`/`dev` counts as production. It drives NGINX tuning, error pages and the dev-mode scaffolding described below.

Each runtime derives its own flag from it unless you set that flag explicitly (`NODE_ENV`, `APP_ENV`/`APP_DEBUG`, `FLASK_ENV` — see the image docs). Explicit values always win, so `ENVIRONMENT=production` + `APP_ENV=staging` is valid: a production-tuned container with a staging app config.

In development, mounting an empty `/container/custom` directory is enough to get the full [customization skeleton](#the-custom-directory) created for you on boot, so you can discover the available directories by looking at them.

## MAX_UPLOAD_SIZE and Friends

`MAX_UPLOAD_SIZE` (default `100M`) sets all upload-related limits at once. The read-only `MAX_UPLOAD_SIZE_BYTES` variable contains the parsed byte value for applications that want an integer.

As a rule of thumb use `MAX_UPLOAD_SIZE`, and only override the individual settings (e.g. `NGINX_CLIENT_MAX_BODY_SIZE`) when values must genuinely differ.

## Path Composition

Multiple services behind one reverse proxy compose their public URL from three variables:

| Variable | Meaning | Example |
|---|---|---|
| `DOCKER_PROJECT_PATH` | Base path of the whole project group | `/project-alpha/` |
| `DOCKER_SERVICE_PATH` | This service's sub-path (default `/`) | `/api/` |
| `DOCKER_SERVICE_ABS_PATH` | Read-only combination of both | `/project-alpha/api/` |

The outer proxy routes on `SERVICE_PATH`; application code generates absolute links with `SERVICE_ABS_PATH`. Example: project at `/project-alpha`, API at `/api` → `DOCKER_PROJECT_PATH=/project-alpha`, `DOCKER_SERVICE_PATH=/api` → `ABS_PATH=/project-alpha/api/`.

## HTTP vs. HTTPS

`DOCKER_PROJECT_PROTOCOL` (default `http`) decides the public protocol:

- **Direct HTTPS:** set `DOCKER_PROJECT_PROTOCOL=https` → NGINX listens on 443 and redirects 80→443. Mount certificates into `/container/custom/certs/` (see [SSL Certificates](#ssl-certificates)); without them, self-signed certificates are generated with a warning (development only).
- **Terminated at an outer gateway (recommended for production):** set `DOCKER_PROJECT_PROTOCOL=https` **and** `DOCKER_SERVICE_PROTOCOL=http` → the container speaks plain HTTP internally but knows the public side is secure.
- Application code should trust `X-Forwarded-Proto`, not the internal listen port.

`DOCKER_PROJECT_PROTOCOL` defines how the **end user** connects; `DOCKER_SERVICE_PROTOCOL` defines how an outer proxy talks to **this container**. It defaults to `DOCKER_PROJECT_PROTOCOL` — set it to `http` when TLS is terminated in front of the container.

> **Production note:** for automated certificate management (e.g. Let's Encrypt), running a dedicated gateway like [linuxserver/swag](https://docs.linuxserver.io/images/docker-swag) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) in front of these containers centralizes SSL management and keeps the application containers simple.

## NGINX DNS Resolution

NGINX resolves dynamic upstream names — a variable in `proxy_pass`, like `proxy_pass http://$backend;` — on every request through the servers of its `resolver` directive. It never consults `/etc/resolv.conf` for those, so the entrypoint fills the resolver snippet from the container's actual nameservers on every boot:

- Docker (user-defined networks) → the embedded Docker DNS at `127.0.0.11`
- Kubernetes → the cluster DNS
- Podman / host networking → the runtime or host resolvers

Override the detected servers with `NGINX_RESOLVER` (space-separated list for multiple servers); `NGINX_RESOLVER_VALID_TIMEOUT` (default `30s`, the `valid=` cache TTL for resolved addresses) and `NGINX_RESOLVER_TIMEOUT` (default `5s`, the query timeout) tune the corresponding `resolver` directives.

> **Kubernetes note:** NGINX's resolver does not apply the `search` / `ndots` options from `/etc/resolv.conf`. Use fully qualified service names (`service.namespace.svc.cluster.local`) for variable-based upstreams — short names like `my-service` will not resolve.

## Basic Authentication

Every image that ships NGINX can protect itself with HTTP basic auth entirely through environment variables — no `htpasswd` utility or mounted password file needed. The entrypoint hashes the passwords (`openssl passwd -apr1`, the MD5-based format NGINX accepts) and writes the password file on every boot, so changing a password is an environment change plus a restart, not a rebuild.

- **Global (whole server, every mode):** `NGINX_BASIC_AUTH` enables it, `NGINX_BASIC_AUTH_1`, `NGINX_BASIC_AUTH_2`, … add users (any combination of numbered suffixes works, empty values are ignored), `NGINX_BASIC_AUTH_REALM` names the login dialog (default `Restricted`).
- **Per proxied service (nginx image, proxy mode):** the same scheme with a `PROXY_<KEY>_` prefix (`PROXY_API_BASIC_AUTH`, `PROXY_API_BASIC_AUTH_2`, `PROXY_API_BASIC_AUTH_REALM`) protects only that service's location and **replaces** the global auth there — its users apply, the global users do not.

The value format is `username clear-password` — the **first space** separates the two, so passwords may contain spaces. A malformed value (missing password, empty username, a `:` in the username, tabs or line breaks in the password) aborts the boot with an error, so a typo can never silently disable the protection.

Hard limits to plan around:

- **Passwords longer than 256 characters are rejected at boot.** `openssl passwd -apr1` silently truncates after 256 characters — a longer password would hash to its 256-character prefix and every login would fail with a cryptic mismatch.
- **The realm must not end in a backslash** (a trailing `\` would escape the closing quote of the generated `auth_basic "…";` directive and corrupt the NGINX configuration). Double quotes, `$`, tabs and line breaks are rejected as well.

### Custom snippets and ownership

NGINX forbids the `auth_basic` directive twice in one context, so the entrypoint checks whether a custom snippet manages authentication before writing its own directives. The rule (`snippet_manages_basic_auth`): a snippet counts as managing basic auth when it contains an `auth_basic` directive — **enabled or `off`** — at **brace depth 0** of the context the snippet is included in (the server context for `nginx/` snippets, the location context for the nginx image's `nginx/proxy/` snippets), evaluated after line-based `#` comment stripping. The six situations:

| Situation | Outcome |
|---|---|
| Global auth set, no snippet owns it | Generated directives apply server-wide. |
| Server-level snippet declares `auth_basic` (enabled) | Takes ownership — the entrypoint skips its generated directives, the snippet's users apply. |
| Server-level snippet with a top-level `auth_basic off;` | Takes ownership — auth is off server-wide. |
| `auth_basic` **nested inside a `location { }` block** | Does **not** take ownership: it only changes that location, and the generated directives stay in place for everything else. |
| Per-proxy auth set, no `<key>…conf` proxy snippet declares `auth_basic` | Generated directives apply to that location. |
| Per-proxy auth set, a proxy snippet declares `auth_basic` | Takes ownership — the generated snippet stays empty; the password file is still written, so the snippet can point `auth_basic_user_file` at `${NGINX_BASIC_AUTH_DIR}/proxy.<key>.htpasswd`. |

The password files are always written (`${NGINX_BASIC_AUTH_FILE}`, `${NGINX_BASIC_AUTH_DIR}`), so an owning snippet can keep the env-var managed users. The generated directives are themselves snippets — `/etc/nginx/snippets/basicAuth.nginx.conf` for the server, `proxy.d/<key>.auth.conf` per proxied service — both always exist and are empty when the respective auth is disabled or owned by a custom snippet; do not name your own snippets like that.

### Health check opt-out (php-nginx)

The `/fpm-ping` and `/fpm-status` locations carry an unconditional `auth_basic off;` **plus `allow 127.0.0.1; deny all;`** — the opt-out exists so health checks from INSIDE the container keep working under a global auth they cannot send credentials for. The access rule is evaluated before authentication, so only in-container probes succeed: an orchestrator HTTP probe from outside (a Kubernetes `httpGet`, a load balancer) is answered **403** by the `deny all;` regardless of any credentials — auth is never even reached. Point such probes at an exec-based check instead (`kubectl exec <pod> -- curl -sf http://localhost/fpm-ping`), or at a location your configuration actually exposes.

### The credentials never leave the entrypoint

`NGINX_BASIC_AUTH(_<n>)` and `PROXY_<KEY>_BASIC_AUTH(_<n>)` hold clear-text passwords, so they are read at boot and never exported anywhere else: they are excluded from the `/container/work/container-vars.sh` snapshot (the file `docker exec` shells and later `RUN` steps source — the boot log prints `Not exporting variable: …` for each) and are `unset` right before the entrypoint execs the container command, so supervisord, nginx, php-fpm (`clear_env = no`!) and every worker run without them. The NGINX configuration references the generated password files, never the variables. The `_REALM`, `_FILE` and `_DIR` companions are not credentials and are exported normally.

### Authorization headers are not forwarded

A proxy location protected by **generated** basic auth (its own per-proxy users, or the global auth when the location has none of its own and no server snippet has taken the global auth over) renders `proxy_set_header Authorization "";` — the client authenticated against *this* server, so forwarding its credentials to the upstream would leak them. Locations owned by a custom snippet and the image's own application runtime are untouched.

## The Custom Directory

**All customization happens through a single mount point:** `/container/custom`, usually `./docker/custom:/container/custom`.

```
custom/
├── env/            # *.env / *.env.sh variable declarations (loaded before services)
├── nginx/          # server-level snippets → /etc/nginx/snippets/…
│   ├── global/     # http-level snippets
│   └── location/   # root-location snippets (web/static mode)
├── certs/          # cert.pem + key.pem
├── entrypoint/     # startup hook scripts
└── <runtime>/      # image-specific (php/, php/fpm/, …) — see the image docs
```

**Read-only mounts (e.g. Kubernetes config maps) are fully supported.** The entrypoint only ever *reads* from `/container/custom` — rendered copies land in the internal work directory — so the mount can be immutable, and the container will not try to change the ownership of the mounted files. The nginx image additionally supports per-service snippets in `nginx/proxy/` (see its documentation).

Mount a config map directly:

```yaml
volumeMounts:
  - name: custom-config
    mountPath: /container/custom
    readOnly: true
# …
volumes:
  - name: custom-config
    configMap:
      name: my-app-custom
```

## Running on a Read-Only Filesystem

The images support `readOnlyRootFilesystem: true` (Kubernetes) and `docker run --read-only`. Everything the container writes at runtime goes to two places:

1. **`/container/work`** — all rendered configuration. Mount it writable; it may start **empty** (tmpfs, `emptyDir`) — the entrypoint seeds it from the image's pristine build state (`/container/work-data-staging`) on every boot, and resets it to that state on every restart, so stale configuration from a previous boot is always discarded. The writable home of the `www-data` service user (`/container/work/www-data-home`, `CONTAINER_WWW_DATA_HOME_DIR`) lives here too; it is **not** reset, so caches and dotfiles survive restarts — budget your tmpfs/`emptyDir` size accordingly.
2. **Runtime directories** — `/run`, `/tmp`, `/var/lib/nginx`, `/var/log/nginx`. Mount them as tmpfs.

Docker:

```bash
docker run --read-only \
  --tmpfs /run --tmpfs /tmp --tmpfs /var/lib/nginx --tmpfs /var/log/nginx \
  -v my-work:/container/work \
  my-image
```

Kubernetes:

```yaml
containers:
  - name: app
    # readOnlyRootFilesystem is a CONTAINER-level setting — at pod level it is
    # rejected (kubectl strict validation, the default since 1.27) or silently
    # ignored by lenient tooling; the root filesystem stays writable.
    securityContext:
      readOnlyRootFilesystem: true
    volumeMounts:
      - { name: work,      mountPath: /container/work }
      - { name: run,       mountPath: /run }
      - { name: tmp,       mountPath: /tmp }
      - { name: nginx-lib, mountPath: /var/lib/nginx }
      - { name: nginx-log, mountPath: /var/log/nginx }
volumes:
  - { name: work,      emptyDir: {} }
  - { name: run,       emptyDir: { medium: Memory } }
  - { name: tmp,       emptyDir: { medium: Memory } }
  - { name: nginx-lib, emptyDir: {} }
  - { name: nginx-log, emptyDir: {} }
```

> **PUID/PGID limitation:** the `PUID`/`PGID` user remapping (see the variable tables of the image docs) is **not supported** on a read-only root filesystem — the remap rewrites `/etc/passwd`/`/etc/group` (`usermod`/`groupmod`, plus their lock files), which cannot be written there. The boot detects this in the user-setup step and aborts cleanly — `[ENTRYPOINT.user-setup] Error: PUID/PGID are not supported with a read-only root filesystem (cannot update /etc/passwd and /etc/group). Aborting.` (exit 1) — instead of dying in a raw `usermod`/`groupmod` lock error or silently booting with the default ownership. The exception: `PUID=33`/`PGID=33` (the ids `www-data` already has) needs no write at all and keeps booting.

## The www-data Home Directory

Every process running as `www-data` (supervisor services with `user=www-data`, `gosu` worker commands, wrapped CLIs like `pip`/`npm`/`composer`, FPM workers) gets the writable home **`/container/work/www-data-home`** (`CONTAINER_WWW_DATA_HOME_DIR`, read-only constant), so libraries that write to `~/` at import or runtime (playwright, huggingface, matplotlib, …) work. It is inside the work directory, so it is writable on read-only filesystems too, and it is not part of the per-boot work-data reset.

- **Do not bake build-time content into `$HOME`.** With `USER www-data` + `RUN playwright install` / `pip install --user` / `composer global require`, the content lands in `/container/work/www-data-home` — hidden behind a tmpfs/`emptyDir` mount at runtime, and with a named volume at `/container/work` it is copied only on the *first* mount, so image upgrades keep stale content (e.g. mismatched playwright browsers). Use explicit paths instead: `PLAYWRIGHT_BROWSERS_PATH`, `COMPOSER_HOME`, `PIP_CACHE_DIR`, …
- **Legacy dotfiles under `/var/www`** (the old www-data home: `.npmrc`, `.ssh`, `.gitconfig`, `.composer`, `.netrc`, …) are bridged into the new home as symlinks at boot, with a deprecation warning — move them to the new home when you can. Note: writes through a bridged entry still land in `/var/www`, which is unwritable on read-only systems (as before).
- Custom supervisor programs that use `user=www-data` should add `environment=HOME="${CONTAINER_WWW_DATA_HOME_DIR}"` to their program section — supervisor's `user=` switches only the uid. Processes launched via `gosu` (and php-fpm workers) derive `HOME` from the www-data passwd entry automatically and need nothing.

## Behavior Changes (Migration Notes)

Breaking or behavior-changing releases are documented in [`docs/migration/`](./migration/), one file per change, each prefixed with the release date (`YYYY-MM-DD-…`). Current transitions:

- [2026-11-12: Build Mode Marker and RUN Variables](./migration/2026-11-12-build-mode-marker-and-variables.md) — builder-stage-only build mode, variables for later `RUN` steps fixed
- [2026-11-12: Exact Command Arguments](./migration/2026-11-12-exact-command-arguments.md) — exact argv execution, single-string deprecation fallback
- [2026-11-12: www-data Home Directory](./migration/2026-11-12-www-data-home-directory.md) — the home move and its dotfile bridge, npm/composer cache paths
- [2026-11-16: Proxy Snippet Include Pattern](./migration/2026-11-16-proxy-snippet-include-pattern.md) — per-service proxy snippets must be named `<key>.<name>.conf` (dot after the key); the old `<key>*.conf` form is dropped

One behavior change without its own guide: gunicorn's supervisor stop wait rises from 10s to `GUNICORN_GRACEFUL_TIMEOUT + 10` (default 40s, python-nginx) — see `GUNICORN_STOP_WAIT_SECS` in [python-nginx.md](./python-nginx.md).

## Customizing the Container

### NGINX Snippets

`MARKER-AWARE` `TEMPLATES`

Place `.conf` files in `nginx/` (server-level snippets, included by the main server block) or `nginx/global/` (http-level, for `map` blocks and global rules). After [templating](#templating) they are copied to `/etc/nginx/snippets/custom.d/` and `/etc/nginx/snippets/global.d/` respectively.

```
docker/custom/nginx/
├── 01-custom-headers.conf
├── 02-rate-limiting.prod.conf
└── global/
    └── 01-gzip-settings.conf
```

The nginx image offers per-service snippets for proxy mode (`nginx/proxy/`), the runtime images root-location snippets (`nginx/location/`) — both are documented in the respective image doc.

### SSL Certificates

`TEMPLATES`

Place `cert.pem` and `key.pem` in `certs/`. When `DOCKER_SERVICE_PROTOCOL="https"`, NGINX uses them (defaults to the project protocol). If none are found, self-signed certificates are generated with a warning — development only.

### Custom Error Pages

`TEMPLATES`

Place `errorPage.html` and/or `errorPage.json` in `nginx/` to replace the built-in error pages for 400, 401, 403, 404, 500, 502, 503, 504. The templates support variable substitution including `${ERROR_CODE}`, `${ERROR_TITLE}` and `${ERROR_DESCRIPTION}`:

```html
<!-- docker/custom/nginx/errorPage.html -->
<h1>${ERROR_CODE}</h1>
<p>${ERROR_DESCRIPTION}</p>
<p>Environment: ${ENVIRONMENT}</p>
```

### Environment Files

`MARKER-AWARE`

The canonical place for project-level derived or dynamic variables — instead of scattering them across Dockerfile `ENV`, compose `environment:` and `-e` flags. Place `*.env` (plain key=value, auto-exported, `${VAR}` references expand at load time) or `*.env.sh` (real shell, must `export` explicitly) in `env/`. Files load in alphabetical order before any service configuration runs. `*.env.sh` files can run arbitrary shell logic (e.g. fetching a value from a secrets manager):

```bash
# docker/custom/env/20-dynamic.env.sh
export CACHE_TTL=$(fetch-from-secrets-manager cache_ttl 2>/dev/null || echo "3600")
```

```dotenv
# docker/custom/env/10-routing.env
APP_URL=${APP_PROTOCOL}://${APP_HOST}
```

### Entrypoint Hooks

`MARKER-AWARE`

Place `.sh` files in `entrypoint/` to run them during startup, just before the services launch. The full environment is available; hooks are plain scripts, not templates (`[[DEBUG_VARS]]` is not available — use `printenv | sort`).

### Overriding Core Templates (Advanced)

`TEMPLATES`

For maximum control, mount your own version of a default template at its exact path to replace it wholesale — e.g. `/container/templates/nginx/nginx.conf`, `/container/templates/python/gunicorn.conf.py` or `/container/templates/php/x.php.ini`. All-or-nothing; filename markers do **not** apply.

### Complete Example

```
project/
├── docker-compose.yml
└── docker/
    └── custom/
        ├── env/
        │   └── 10-routing.env
        ├── nginx/
        │   ├── global/
        │   │   └── 01-cors.conf
        │   ├── 01-custom-location.conf
        │   ├── errorPage.html
        │   └── errorPage.json
        ├── certs/
        │   ├── cert.pem
        │   └── key.pem
        └── entrypoint/
            └── 01-setup.sh
```

## Templating

Every config file — built-in templates **and** every file in `/container/custom` — is rendered with `${VAR}` substitution from the exported environment (bash parameter expansion, no external engine). Variables must be `UPPERCASE`; lowercase and `_`-prefixed names are ignored.

Add `[[DEBUG_VARS]]` on its own line anywhere in a file to make the entrypoint print every substitutable variable with its value and exit — not available in entrypoint hooks.

## Filename Markers

Loading conditions live in filenames, so a directory listing shows what will load when. Applies to custom snippets, env files and entrypoint hooks — **not** to core template overrides.

`.` splits the filename into AND-groups; every group containing a known marker must be satisfied. `-or-` builds OR clauses inside one group. Non-marker groups (like `conf`, `ini`, `sh`) are ignored.

| Marker | Condition | Example |
|---|---|---|
| `prod` / `dev` | `ENVIRONMENT` is production / development | `10-security.prod.conf` |
| `env-*` | `ENVIRONMENT` matches (`env-prod`/`env-dev` alias production/development; custom values like `env-staging` work) | `30-analytics.env-staging.conf` |
| `mode-*` | `CONTAINER_MODE` matches | `02-clear-cache.mode-web.sh` |
| `https` | `DOCKER_SERVICE_PROTOCOL=https` | `03-websockets.https.conf` |

`20-hsts.prod.https.conf` = production **and** https. `30-analytics.prod-or-env-staging.conf` = production **or** staging.

## Utility Commands

Anything in `/container/bin` is callable as a shell command — works on read-only filesystems, no Dockerfile changes needed.

- **`reload-supervisor`** — apply changed configs without a container restart: `docker exec my-container reload-supervisor` (runs `supervisorctl restart all`).

The runtime images add their own commands (env-wrapped CLIs like `php`, `python`/`pip` and `node` — see the image docs).

## Supervisor and Fatal Failures

All services run under Supervisor. A process failing to start 3 times in quick succession is marked `FATAL`; an event listener then exits the whole container so a dead worker can never hide inside a healthy-looking container. Combine with `restart: unless-stopped` for self-healing.

## Worker Mode

Set `<RUNTIME>_WORKER_COMMAND` (e.g. `PHP_WORKER_COMMAND`, `NODE_WORKER_COMMAND`, `PYTHON_WORKER_COMMAND`) and the image runs your command under Supervisor instead of the web server — same environment, same entrypoint, same customization. The variable name per image is listed in its documentation.

Graceful shutdown: `*_WORKER_STOP_WAIT_SECS` defines how long the worker may finish after SIGTERM. Docker sends `SIGKILL` 10 seconds after `SIGTERM` by default, so `stop_grace_period` must be raised **above** the wait time or it never takes effect:

```yaml
stop_grace_period: 120s
environment:
  - PHP_WORKER_COMMAND=php /var/www/html/artisan queue:work
  - PHP_WORKER_STOP_WAIT_SECS=90
```

## Build Mode

`RUN init-build-env` in a Dockerfile runs the full entrypoint bootstrap for build stages: same environment as production, services skipped. It is **only for builder stages** of a multi-stage build — images built this way refuse to boot by design, and if that ever happens by accident, the startup error explains the fix:

```dockerfile
FROM neunerlei/php-nginx:latest AS builder
ENV DOCKER_PROJECT_PROTOCOL=https
COPY --chown=www-data:www-data ./src ./src
RUN init-build-env
RUN composer install --no-dev --optimize-autoloader

FROM neunerlei/php-nginx:latest
COPY --from=builder /var/www/html ./
```

**CI:** to start a builder-stage image anyway (e.g. `docker build --target builder` followed by `docker run … phpunit`), build it with `RUN init-build-env --allow-boot` — no marker is written and the image can boot. Changes made by later `RUN` steps (e.g. a `docker-php-ext-enable` dropping a conf.d file) **survive boots**: the rendered work data is synced back into the staging area. Caveat: build-time rendered configuration — including anything rendered from build-time env values — becomes part of the image, so don't render secrets at build time.

**Deprecated legacy invocation:** running the entrypoint itself without a command (`RUN /container/entrypoint/entrypoint.sh`) still works as a compatibility layer until **2027-11-12** (see the [migration guide](./migration/2026-11-12-build-mode-marker-and-variables.md)). It behaves like `init-build-env --allow-boot` — no marker, the image stays bootable — but logs a deprecation warning on every build-mode run. New Dockerfiles use `init-build-env`.

### Variables in Later `RUN` Steps

Later `RUN` steps see exactly the variables production will have — same paths, same derived values:

- **Shell-form `RUN`** (the usual `RUN pnpm build`) runs through `/bin/sh`, which links to the [bash wrapper](#the-shell-environment-and-the-bash-wrapper) and sources the `container-vars.sh` snapshot the build-mode run wrote.
- **Exec-form `RUN` `["…"]`** only receives the variables through the env-wrapped binaries (`node`, `python`, `pip`, `php`, …) — start the exec form with a wrapped binary, or use the shell form.

Run your build commands in a **separate `RUN`** after `init-build-env`. Chaining in the same line (`RUN init-build-env && npm run build`) only gives the variables to env-wrapped child processes — the outer shell started before the snapshot existed, so `$NODE_ENV` in the `RUN` line itself is empty.

The file is a **snapshot** taken at the build-mode run: it takes precedence over `ENV` lines declared *after* it. Declare all `ENV` lines before `init-build-env`; to re-run after changing `ENV`, use the exec form `RUN ["init-build-env"]` — the shell form goes through the bash wrapper, which sources the old snapshot and would override the new `ENV`. `HOME` is deliberately not part of the snapshot.

Builder images pushed to a registry (e.g. as a CI cache) contain the derived variables, including everything computed by `custom/env` files — don't pull secrets in at build time.

### Build Hooks

Hooks can target the build phase only (`01-migrations.mode-build.sh`).

## The Shell Environment and the Bash Wrapper

Entrypoint-exported variables are normally invisible to `docker exec` sessions. These images solve it with a bash wrapper: during the build, `/bin/bash` is moved to `/bin/_bash` and replaced by a script that sources `/container/work/container-vars.sh` (written by the entrypoint) before exec-ing the real bash. `/bin/sh` symlinks to it too.

**Implications:**

- `docker exec my-container bash` sees `DOCKER_SERVICE_ABS_PATH` and friends.
- Other shells (zsh) must source `/container/work/container-vars.sh` in their rc.
- Runtime CLIs are env-wrapped the same way — `php` (php-nginx), `python` and `pip` (python-nginx), `node` (node-nginx) — so `docker exec my-container node script.js` sees the container variables too; prefix `_` (e.g. `_node`) for the originals.

**Container values take precedence over inline overrides.** `container-vars.sh` exports every variable unconditionally, so each wrapped binary resets them to the container's values — `NODE_ENV=test node --test` or `docker exec -e APP_ENV=testing my-container php artisan test` run with the container's `NODE_ENV`/`APP_ENV`. Variables that don't exist in the container environment are not affected.

- To keep an override for a single call, invoke the original binary: `NODE_ENV=test _node --test`. Anything that process spawns through `sh`, `bash` or another wrapped CLI (npm/composer scripts, `exec()` calls) gets the container values again.
- To change a value permanently, set it where the container gets its environment — compose `environment:` or an [environment file](#environment-files) — so the entrypoint exports the value you want.

## Migration from Legacy Mount Points

> **Breaking change:** all customization paths were centralized into `/container/custom`.

Containers mounting legacy paths (`/etc/ssl/certs`, `/etc/container/templates/nginx/custom`, `/usr/bin/container/custom`) **fail to start** with an error message containing migration instructions. See the [migration guide](./migration/2026-02-05-migrate-to-centralized-container-dir.md) for details.
