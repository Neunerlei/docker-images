# `neunerlei/node-nginx` — Node.js + NGINX

Node.js app behind NGINX reverse proxy, both in one container, managed by Supervisor.

## Quick start

```yaml
services:
  app:
    image: neunerlei/node-nginx:latest
    ports: ["8080:80"]
    volumes:
      - ./your-node-project:/var/www/html
    environment:
      - ENVIRONMENT=dev          # shows a helpful page with env vars via default server.js
      - MAX_UPLOAD_SIZE=250M
```

App code goes to `/var/www/html`. NGINX serves static files from `/var/www/html/public` first, then proxies to the Node app (`@nodeproxy`).

## npm and pnpm

Both installed. Both ALWAYS run as `www-data` — no permission worries from root shells. For global package installs or running as another user, call the unwrapped originals: `_npm`, `_pnpm`.

`node` itself is env-wrapped like bash: `node script.js` and `docker exec … node` see entrypoint vars; `_node` is the original. Container values take precedence over inline overrides like `NODE_ENV=test node …` — see SKILL.md.

## Modes

- **web** (default): NGINX (reverse proxy) + your Node server.
- **worker**: set `NODE_WORKER_COMMAND` → NGINX off, Supervisor runs your command.
- **build**: entrypoint in a Dockerfile `RUN` without a command.

## Variables (image-specific)

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | derived from `ENVIRONMENT` | Standard Node env var; explicit value wins. |
| `NODE_WEB_COMMAND` | `node /var/www/html/server.js` | Start command for web mode. |
| `NODE_SERVICE_PORT` | `3000` | Port the Node app listens on (NGINX proxies here). |
| `NODE_WORKER_COMMAND` | (unset) | **Setting this enables worker mode.** |
| `NODE_WORKER_PROCESS_COUNT` | `1` | Supervisor `numprocs`. |
| `NODE_WORKER_STOP_WAIT_SECS` | `10` | Supervisor `stopwaitsecs`; needs `stop_grace_period` above it. |
| `NGINX_TRY_FILES` | `$uri @nodeproxy` | Static-first, then proxy to Node. |

## Worker examples

```yaml
my-app-worker:
  image: neunerlei/node-nginx:latest
  volumes: [./your-node-project:/var/www/html]
  restart: unless-stopped
  environment:
    - NODE_WORKER_COMMAND=node /var/www/html/dist/queue-worker.js
    - NODE_WORKER_PROCESS_COUNT=4
# "cron" without cron: NODE_WORKER_COMMAND=while true; do node my_task.js; sleep 300; done
```

## Image-specific customization (`/container/custom`)

Shared dirs plus:

| Dir | Loaded into |
|---|---|
| `nginx/` | Server block (→ `/etc/nginx/snippets/custom.d/`). |
| `nginx/global/` | `http` block. |
| `nginx/location/` | Root `location /` block — auth, headers, rewrites. Cannot override `try_files` (use `NGINX_TRY_FILES`). |

## Build mode

```dockerfile
FROM neunerlei/node-nginx:latest AS builder
ARG DOCKER_PROJECT_HOST
ENV DOCKER_PROJECT_HOST=${DOCKER_PROJECT_HOST}
COPY --chown=www-data:www-data ./package*.json ./
COPY --chown=www-data:www-data ./src ./src
RUN /container/entrypoint/entrypoint.sh      # env now matches production
RUN npm ci && npm run build

FROM neunerlei/node-nginx:latest
WORKDIR /var/www/html
COPY --from=builder /var/www/html/dist ./dist
COPY --from=builder /var/www/html/package*.json ./
COPY --from=builder /var/www/html/node_modules ./node_modules
```

## Defaults

Ships `server.js` at `/var/www/html/server.js`: basic server, welcome page, env var list when `NODE_ENV=development`. Replace by mounting your project or pointing `NODE_WEB_COMMAND` elsewhere.
