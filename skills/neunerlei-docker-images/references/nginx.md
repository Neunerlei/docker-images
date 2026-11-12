# `neunerlei/nginx` — Smart Reverse Proxy / Static Server

Not an app runtime: a standalone NGINX that either reverse-proxies to sibling containers or serves static files. The entrypoint detects the mode from env.

## Modes

- **proxy** (main mode): any `PROXY_*_CONTAINER` variable present → builds one `location` block per service key. Project base path supported via `DOCKER_PROJECT_PATH` (combined with each service path).
- **static** (fallback, no `PROXY_*` vars): serves files from `NGINX_DOC_ROOT` (`/var/www/html/public`). Ships a default `index.html` — mount your own files to replace it.

`MAX_UPLOAD_SIZE` sets `client_max_body_size` only in proxy mode (all uploads pass through the proxy).

## Proxy service variables

Define a group per service with a unique key (`FRONTEND`, `API`, …):

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `PROXY_<KEY>_CONTAINER` | yes | — | Hostname of the backend (usually the Compose service name). |
| `PROXY_<KEY>_PATH` | no | `/` | Public path for this service. |
| `PROXY_<KEY>_DEST` | no | — | Rewrite target. `_PATH=/api` + `_DEST=/` routes `/api/users` → `/users`. |
| `PROXY_<KEY>_PROTOCOL` | no | `http` | Backend protocol. |
| `PROXY_<KEY>_PORT` | no | `80` | Backend HTTP port. |
| `PROXY_<KEY>_HTTPS_PORT` | no | `443` | Backend HTTPS port. |
| `PROXY_<KEY>_BASIC_AUTH` | no | — | Basic auth for only this service's location: `username clear-password`. |
| `PROXY_<KEY>_BASIC_AUTH_1..n` | no | — | Additional users for this service. |
| `PROXY_<KEY>_BASIC_AUTH_REALM` | no | `Restricted` | Login-dialog realm for this service. |

```yaml
proxy:
  image: neunerlei/nginx:latest
  ports: ["80:80"]
  environment:
    - PROXY_FRONTEND_CONTAINER=frontend-app   # / → frontend-app:3000
    - PROXY_FRONTEND_PORT=3000
    - PROXY_API_CONTAINER=backend-app        # /api/* → backend-app:80 as /*
    - PROXY_API_PATH=/api
    - PROXY_API_DEST=/
```

Backends are addressed via `proxy_pass $upstream` (dynamic name) → resolution runs through the auto-detected NGINX resolver on every request; in Kubernetes backend names must be FQDNs (see SKILL.md → NGINX DNS resolution).

## Static mode

| Variable | Default | Purpose |
|---|---|---|
| `NGINX_DOC_ROOT` | `/var/www/html/public` | Document root for static files. |
| `NGINX_TRY_FILES` | `$uri $uri/ /index.html /index.htm =404` | Root-location routing (SPA-friendly). |

## Basic authentication

Env-var driven, regenerated every boot; passwords hashed with `openssl passwd -apr1`, htpasswd files land in `/container/work/nginx-basic-auth/`. The generated `auth_basic` directives are regular snippets: `/etc/nginx/snippets/basicAuth.nginx.conf` (server context, registered via the `nginx-snippets-basic-auth` tpl) and `proxy.d/<key>.auth.conf` per service (auto-included by the location's custom-snippet glob) — always present, empty when disabled.

- **Global (all images, whole server):** `NGINX_BASIC_AUTH="user clear-pass"`, extra users `NGINX_BASIC_AUTH_1..n` (any suffix combo, empty values ignored), realm `NGINX_BASIC_AUTH_REALM` (default `Restricted`). First space separates user/password — passwords may contain spaces. Generated file path available as `NGINX_BASIC_AUTH_FILE`.
- **Per service (this image, proxy mode):** `PROXY_<KEY>_BASIC_AUTH(_1..n/_REALM)` — replaces the global auth for that location only (its users apply, global users don't).
- **Ownership rule:** a snippet declaring `auth_basic` — including `auth_basic off;` — takes ownership of its context; the entrypoint then skips its generated directives there (NGINX forbids the directive twice). Password files are always written, so an owning snippet can point `auth_basic_user_file` at `${NGINX_BASIC_AUTH_DIR}/proxy.<key>.htpasswd` (or `${NGINX_BASIC_AUTH_FILE}`) and keep the env-managed users.
- Boot log prints every configured user with password length — compare against expectations when logins fail (env parsers may truncate at `#`/`$`); verify with `printenv NGINX_BASIC_AUTH` in the container.
- Error pages stay reachable without credentials (the `@error_handler` location disables auth).
- Malformed values abort the container at boot instead of serving unprotected.

## Image-specific customization (`/container/custom`)

Beyond the shared dirs (`env/`, `certs/`, `entrypoint/`, `errorPage.html/json`):

| Dir | Loaded into | Notes |
|---|---|---|
| `nginx/` | server block | Server-level snippets → `/etc/nginx/snippets/custom.d/`. |
| `nginx/global/` | `http` block | Global rules, headers, `map` blocks. |
| `nginx/location/` | root `location` block (static mode) | Cannot override `try_files` — use `NGINX_TRY_FILES`. |
| `nginx/proxy/` | per-service `location` block (proxy mode) | Filename = lowercase service key + `.` + any name: `api.cache.conf` targets `PROXY_API_*` (the dot is the key boundary — `api` and `api_v2` don't collide); markers allowed: `api.prod-or-env-staging.https.conf`; bare `api.conf` works for backward compat. |

Example per-service snippet:

```nginx
# nginx/proxy/api.cache.conf — inside the API service's location block
proxy_cache_valid 200 10m;
proxy_cache_key "$scheme$request_method$host$request_uri";
```
