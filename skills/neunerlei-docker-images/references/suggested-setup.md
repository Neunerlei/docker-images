# Suggested project setup

Recommended repository layout for a project running on these images: one multi-target `Dockerfile`, a dev compose (sources bind-mounted), a prod compose (pushed images behind an outer proxy), tests running in containers. Everything optional. Full guide with CI wiring: `docs/suggested-setup-and-usage.md`.

## Contents

- [Idea](#idea) — one Dockerfile, four targets; tests need only Docker
- [Multi-target Dockerfile](#multi-target-dockerfile) — base/dev/test/builder/prod stages
- [Dev compose](#dev-compose) — bind mounts, host ids, localhost ports
- [Tests](#tests) — `run --rm`, profiles, heavy deps
- [Prod compose](#prod-compose) — baked image, external proxy network, no ports
- [CI pipeline](#ci-pipeline) — test → push (sha tags) → deploy webhook
- [Adapting to other images](#adapting-to-other-images) — per-runtime commands

## Idea

One `Dockerfile`, four targets: **dev** (repo bind-mounted over the image at runtime), **test** (sources + dev dependencies baked in, runs the suite), **builder** (prod env, install + build), **prod** (boot artifacts + custom dir baked). One compose file per environment selects the target, so dev and prod share one definition instead of drifting apart. Tests run inside the test target — contributors and CI need nothing but Docker.

```
.
├── Dockerfile                  # one file, four targets
├── docker-compose.yml          # dev: builds dev target, bind-mounts sources
├── docker-compose.prod.yml     # prod: runs pushed images, no published ports
├── docker/
│   ├── app/                    # the project's /container/custom content
│   │                           # (nginx snippets, entrypoint hooks, env files)
│   └── certs/                  # optional TLS certs for local https (gitignored)
└── .github/workflows/deploy.yml  # tests → build & push → deploy webhook
```

`docker/app` IS the custom-dir content. Dev bind-mounts it (edits live, no rebuild); prod bakes it into the image (self-contained; entrypoint never needs write access to the custom dir).

## Multi-target Dockerfile

Node example; the shape is identical for every image — only install/build commands and the web-process variable change.

```dockerfile
FROM neunerlei/node-nginx:24 AS app_base
RUN apt-get update && apt-get install -y --no-install-recommends <runtime-tools> \
    && rm -rf /var/lib/apt/lists/*

FROM app_base AS app_dev        # usually empty; exists so dev/prod differ explicitly

FROM app_base AS app_test       # sources + FULL install (dev deps included)
COPY --chown=www-data:www-data . .
RUN init-build-env --allow-boot # test target IS booted → no boot-refusal marker
RUN pnpm install --frozen-lockfile

FROM app_base AS builder        # prod env; never booted, artifacts copied out
COPY --chown=www-data:www-data . .
RUN init-build-env              # writes marker → stage refuses to boot later
RUN pnpm install --frozen-lockfile && pnpm build && pnpm prune --prod

FROM app_base AS app_prod
WORKDIR /var/www/html
COPY --from=builder --chown=www-data:www-data /var/www/html/build ./build
COPY --from=builder --chown=www-data:www-data /var/www/html/node_modules ./node_modules
COPY --from=builder --chown=www-data:www-data /var/www/html/package.json ./
COPY --chown=www-data:www-data docker/app /container/custom
ENV NODE_WEB_COMMAND="node /var/www/html/build/index.js"
```

- `init-build-env`, never a bare `RUN /container/entrypoint/entrypoint.sh` (deprecated). The marker makes a builder stage un-bootable — it can never ship as a final image by accident; the booted test target uses `--allow-boot`.
- Dependencies before sources: keep the lockfile-only `COPY` + install ahead of the source `COPY` where the toolchain allows, so source edits don't invalidate dependency layers.

## Dev compose

```yaml
services:
  app:
    build: { context: ., target: app_dev }
    restart: no                 # a dead dev container stays dead and visible
    volumes:
      - ./:/var/www/html        # live sources
      - ./docker/app:/container/custom
      - app_data:/data          # persistent state
    environment:
      ENVIRONMENT: dev
      PUID: ${PUID:-1000}       # host ids → bind-mount writes land host-owned
      PGID: ${PGID:-1000}
      NODE_SERVICE_PORT: '5173'
      # quoting keeps the && chain in ONE sh argument (supervisor shlex-splits)
      NODE_WEB_COMMAND: "sh -lc 'pnpm install && pnpm dev --host'"
    ports: ['127.0.0.1:5173:5173']  # localhost only
    extra_hosts: [host.docker.internal:host-gateway]  # reach host services

  node-test:
    build: { context: ., target: app_test }
    profiles: ['test']          # keeps it out of plain `docker compose up`
    restart: no
    command: sh -lc 'pnpm check && pnpm test'

volumes:
  app_data: {}
```

## Tests

```sh
docker compose --profile test run --rm node-test
```

`run --rm`, not `up`: `run` propagates the suite's exit code; `up` reports compose's own status — green pipeline, red suite. Same image runs locally and in CI (exact runtime version + system packages, no host toolchain, no CI setup steps). Heavy dependencies fine: install browsers in the base/test target (`RUN playwright install …`) and give the service `shm_size: 1gb`.

## Prod compose

```yaml
services:
  app:
    image: ${APP_IMAGE}         # from the registry; build: docker build --target app_prod
    restart: always
    volumes: [app_data:/data]   # state only — code and config are baked in
    env_file: [.env]
    environment:
      PUID: ${PUID:-1000}       # match whatever wrote /data first
      PGID: ${PGID:-1000}
    healthcheck:
      test: curl --fail http://localhost/api/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks: [default, proxy-network]

networks:
  proxy-network:
    external: true              # created by the outer proxy (Traefik, Dokploy, …)

volumes:
  app_data: {}
```

Notable by absence: no `ports` (the proxy routes + terminates TLS over `proxy-network`), no code/config mounts. Workers (queues, schedulers): same image, a `*_WORKER_COMMAND` instead of the web stack.

## CI pipeline

1. **test** — build + `docker compose --profile test run --rm <test-service>`.
2. **build-and-push** — `target: app_prod` (the deployable image is never the default target); registry paths must be lowercase (`${GITHUB_REPOSITORY,,}` — owner names may contain uppercase); push `<sha>` + `latest` tags.
3. **deploy** — curl the deploy webhook; the platform pulls. Pin production to sha tags; `:latest` is for local convenience.

## Adapting to other images

| Concern | node-nginx | php-nginx | python-nginx |
|---|---|---|---|
| Web process | `NODE_WEB_COMMAND`, `NODE_SERVICE_PORT` | PHP-FPM, automatic | `PYTHON_APP_MODULE` + gunicorn vars |
| Dependency install | `pnpm install --frozen-lockfile` | `composer install` | `gosu www-data pip install -r requirements.txt` |
| Test command | `pnpm test` | `phpunit` / `pest` | `pytest` |
| Build-mode env for tests | `init-build-env --allow-boot` | same | same |
