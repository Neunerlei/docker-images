# `neunerlei/python-nginx` — Gunicorn (WSGI) + NGINX

Python application runtime: NGINX in front, **Gunicorn** as WSGI server behind, talking over a Unix socket. Supervisor-managed.

> **Venv:** everything lives in `/opt/venv` (symlinked as `/var/www/venv`). `python` and `pip` on `PATH` resolve to the venv automatically, and both are wrapped like bash so `docker exec` sessions see entrypoint vars.

## Quick start

```yaml
services:
  app:
    image: neunerlei/python-nginx:latest
    ports: ["8080:80"]
    volumes:
      - ./your-python-project:/var/www/html
    environment:
      - ENVIRONMENT=dev          # default Flask app shows env vars
      - MAX_UPLOAD_SIZE=250M
```

WSGI callable expected at `server:app` (override with `PYTHON_APP_MODULE`).

## Request flow

1. NGINX receives the request (80/443).
2. Tries static file from `/var/www/html/static/` (via `NGINX_TRY_FILES`).
3. Falls through to `@pythonproxy` → Gunicorn via `/run/gunicorn.sock` → your app.

## Modes

- **web** (default): NGINX + Gunicorn.
- **worker**: set `PYTHON_WORKER_COMMAND` → NGINX off, Supervisor runs your command (venv `python` usable directly).
- **build**: entrypoint in a Dockerfile `RUN` without a command.

```yaml
my-app-worker:
  image: neunerlei/python-nginx:latest
  volumes: [./your-python-project:/var/www/html]
  restart: unless-stopped
  environment:
    - PYTHON_WORKER_COMMAND=python /var/www/html/queue_worker.py
    - PYTHON_WORKER_PROCESS_COUNT=4
# "cron": PYTHON_WORKER_COMMAND=while true; do python my_task.py; sleep 300; done
```

## Variables (image-specific)

| Variable | Default | Purpose |
|---|---|---|
| `APP_ENV` | derived from `ENVIRONMENT` | `prod` / `dev`; explicit wins. |
| `FLASK_ENV` | derived from `ENVIRONMENT` | `production` / `development`; explicit wins. |
| `APP_DEBUG` | derived | `1` when `ENVIRONMENT` or `APP_ENV` is dev, else `0`; explicit wins. |
| `PYTHON_APP_MODULE` | `server:app` | WSGI callable in `module:callable` form (e.g. `myapp.wsgi:application`). |
| `GUNICORN_WORKERS` | `4` | Worker process count. |
| `GUNICORN_WORKER_CLASS` | `sync` | Worker type (`gevent`, `uvicorn.workers.UvicornWorker`, …). |
| `GUNICORN_LOG_LEVEL` | `info` | Gunicorn log level. |
| `GUNICORN_SOCKET` | `/run/gunicorn.sock` | Read-only: the Unix socket NGINX proxies to. |
| `GUNICORN_TIMEOUT` | `30` | Worker kill timeout. Raise `NGINX_PROXY_READ_TIMEOUT` (default 60s) with it, or NGINX 504s first. |
| `GUNICORN_GRACEFUL_TIMEOUT` | `30` | Graceful shutdown window before force-kill. |
| `GUNICORN_MAX_REQUESTS` | `0` | Restart workers after N requests (memory leaks); 0 = off. |
| `GUNICORN_MAX_REQUESTS_JITTER` | `0` | Spread worker restarts; without it all recycle at once. |
| `GUNICORN_STOP_WAIT_SECS` | `graceful + 10` | Derived, overridable default. Supervisor `stopwaitsecs` (was 10s); `stop_grace_period` still caps it. |
| `PYTHON_WORKER_COMMAND` | (unset) | **Setting this enables worker mode.** |
| `PYTHON_WORKER_PROCESS_COUNT` | `1` | Supervisor `numprocs`. |
| `PYTHON_WORKER_STOP_WAIT_SECS` | `10` | Supervisor `stopwaitsecs`; needs `stop_grace_period` above it. |
| `NGINX_TRY_FILES` | `/static/$uri @pythonproxy` | Static-first from `static/`, then Gunicorn. |

## Installing dependencies

```dockerfile
FROM neunerlei/python-nginx:latest
COPY --chown=www-data:www-data ./requirements.txt /var/www/html/requirements.txt
RUN pip install --no-cache-dir -r /var/www/html/requirements.txt  # pip always runs as www-data
COPY --chown=www-data:www-data ./src /var/www/html
```

## Image-specific customization (`/container/custom`)

Same layout as the other app images: `env/`, `nginx/` (+ `global/`, `location/`), `certs/`, `entrypoint/`, `errorPage.*`. Core template override example: `/container/templates/python/gunicorn.conf.py`.

## Defaults

Ships `server.py` (Flask app exposing `app`) and a `requirements.txt` with gunicorn + flask at `/var/www/html`. Replace both by mounting your project.
