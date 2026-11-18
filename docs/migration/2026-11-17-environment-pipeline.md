# Migration Guide: Environment Pipeline Reordering

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: a downstream image that overrides the removed step files `step.d/015-image-vars.sh` or `step.d/017-custom-env.sh` keeps working (the overrides are detected by file existence, run with a deprecation warning at exactly the position where the steps used to run, and take precedence exactly like before) until **2027-11-17**. After that point, the layer may be removed at any time and the files are silently ignored — so ensure to upgrade your image until then.

## What Changed

The entrypoint's environment pipeline was reordered ("derive twice, track defaults"). Before, the derived variables — everything computed from other variables — were calculated **before** the custom environment files (`/container/custom/env/*.env`) were loaded, so those derivations were computed from the defaults forever. A `.env` with `MAX_UPLOAD_SIZE=500M` left `MAX_UPLOAD_SIZE_BYTES=104857600` and `NGINX_CLIENT_MAX_BODY_SIZE=100M`.

The fix derives more than once, because a plain "load data first, derive afterwards" order would break `${VAR}` references inside `.env` files (the docs call those files *the canonical place for project-level derived variables* — references like `APP_URL=${APP_PROTOCOL}://${APP_HOST}` expand at load time and must keep seeing the pass-1 values). The new boot sequence, orchestrated by the new `step.d/015-environment.sh`:

1. `derive_common_env` — pass 1: every derived value exists, computed from the container environment (`.env` files may reference them).
2. **LEGACY**: a downstream `step.d/015-image-vars.sh` override runs, if one exists.
3. `image_env_features()` — `CONTAINER_MODE` + `feature_registry`, before the env files are marker-filtered (`mode-*`/`feat-*` markers keep working on env files).
4. `image_env_defaults()` — per-image defaults, pass 1.
5. static `*.env` files load.
6. `derive_common_env` + `image_env_defaults()` — pass 2: the `.env` inputs reach the derived values.
7. dynamic `*.env.sh` files load.
8. `derive_common_env` + `image_env_defaults()` — pass 3: the `.env.sh` inputs too.
9. `image_env_validate()` — checks that only make sense on final values.

Recomputation is safe because every default now goes through the tracked `default_var` helper: a default that is still in place is recomputed when its inputs changed, a value the user set (Dockerfile `ENV`, `docker -e`, env file) is **never** touched.

### Removed files

These step files **no longer exist** in the base images:

- `step.d/015-image-vars.sh` (every image) — its content moved to the per-image `container/entrypoint/image-env.sh`, restructured into three optional functions (`image_env_features`, `image_env_defaults`, `image_env_validate`; see [Contributing](../contributing.md)).
- `step.d/017-custom-env.sh` — loading the custom env files moved into the orchestrator (`util.d/load-custom-env-files.sh`).

This affects downstream images in two different ways:

- **An image that OVERRIDES them** (its own `COPY container /container` ships a file with the same name) keeps working: the compatibility layer detects the file by its existence, logs a deprecation warning, and runs it exactly where the step used to run. A `015-image-vars.sh` override runs *before* the base image's own `image_env_features`/`image_env_defaults`, and its exported values count as user-set — the base fills in only what is still missing. That is exactly the old precedence. A `017-custom-env.sh` override replaces **both** env-file loads (`*.env` and `*.env.sh`).
- **Anything that SOURCES or COPIES our original files** (e.g. a Dockerfile that runs `source /container/entrypoint/step.d/017-custom-env.sh`, or a build pipeline that copies the file out of a base image) breaks **immediately**: the files are gone. Move the logic into your own `container/entrypoint/image-env.sh`, into a `util.d` helper, or into env files.

**Not supported:** an override that *removes* a feature the base image sets. `feature_registry` is additive; a downstream `015-image-vars.sh` copy that omits the base's features cannot switch them off.

## Behavior Changes on Rebuild

You do not need to change anything to benefit — but values from `/container/custom/env/*.env` now **really take effect** for:

- `MAX_UPLOAD_SIZE` → `MAX_UPLOAD_SIZE_BYTES`, `NGINX_CLIENT_MAX_BODY_SIZE`, `PHP_UPLOAD_MAX_FILESIZE`, `PHP_POST_MAX_SIZE` (upload limits now follow an env-file `MAX_UPLOAD_SIZE=500M`)
- `NGINX_PROXY_*_TIMEOUT` → `NGINX_KEEPALIVE_TIMEOUT`
- `DOCKER_PROJECT_PATH` / `DOCKER_SERVICE_PATH` → `DOCKER_SERVICE_ABS_PATH`
- `DOCKER_PROJECT_PROTOCOL=https` → NGINX now really renders the HTTPS configuration (listen 443, redirect) when set in an env file
- the `APP_ENV` family (`APP_ENV`, `APP_DEBUG`, `FLASK_ENV`, `NODE_ENV`) derived from `ENVIRONMENT`
- `NGINX_SERVE_ROOT` / `NGINX_DOC_ROOT` — a custom serve root from an env file now also gets its ownership fixed (the user-owned-directories registry is evaluated after the pipeline)
- `NODE_WEB_COMMAND` (node-nginx): a command from an env file now satisfies the web-mode check

### ⚠️ Security-relevant: `ENVIRONMENT` in env files now applies

An env file with `ENVIRONMENT=development` was previously **ignored for every derived application variable** — `APP_DEBUG` stayed `0`, error output stayed suppressed. After the rebuild it applies for real: `APP_DEBUG=1`, verbose dev error output, dev-tuned NGINX. **Check your env files for `ENVIRONMENT=` before rebuilding** if any of them was written with the assumption it would not take effect.

### Markers

An env file setting `ENVIRONMENT=dev` is now normalized to `development` during the pipeline, so `.dev.`-marked files are really selected. Previously the raw `dev` value never matched the `dev` marker condition.

### `PYTHON_APP_MODULE` quote fix

The python-nginx default of `PYTHON_APP_MODULE` contained literal single quotes (the value was `'server:app'`, quotes included, and reached the gunicorn config that way). The default is now `server:app` without the quotes. If you consumed the old value verbatim, drop the surrounding quotes.

## Caveats

These are properties of the pass model. Caveat 1 applied to the old pipeline in the same way; caveat 2 is **new behavior** introduced by the reordering:

1. **References see load-time values.** A `.env` that sets an input and references the derived value *in the same file* gets the old (pass-1) value — the same as before. `UPLOAD_BYTES=${MAX_UPLOAD_SIZE_BYTES}` next to `MAX_UPLOAD_SIZE=500M` expands to the pass-1 byte count; the corrected value arrives on the next pass, and everything derived from it (nginx config, runtime) uses the corrected value.
2. **A derived variable set to exactly its default counts as "not set by the user".** `NGINX_CLIENT_MAX_BODY_SIZE=100M` (the default) in an env file is indistinguishable from an untouched default and is recomputed when `MAX_UPLOAD_SIZE` changes. **This is new:** before the reordering, nothing re-derived values after the env files loaded, so such an assignment always stayed fixed — an env file pinning `NGINX_CLIENT_MAX_BODY_SIZE=100M` kept 100M even next to `MAX_UPLOAD_SIZE=500M`; now it follows the 500M. To pin a derived value, either set it to something *different* from its default, set the input instead (e.g. only `MAX_UPLOAD_SIZE` and let everything derive from it), or — the reliable way to keep a value at exactly its default — pass it via `docker -e` / Compose `environment:` instead of an env file: container-environment values exist before step 015 and are never recorded as defaults, so no pass ever touches them.
3. **Marker filtering happens per pass.** `*.env` files are filtered using the container-environment values; `*.env.sh` files are filtered using the values after the `.env` pass.
4. **Mode and features cannot be changed from env files.** `PYTHON_WORKER_COMMAND`, `NODE_WORKER_COMMAND` or `PHP_WORKER_COMMAND` in a `.env` have no effect — `CONTAINER_MODE` is decided before the env files load, because the files are marker-filtered by it. That is unchanged behavior, not a regression.

## Notes

- The deprecation warning for an overridden step file looks like this (once per boot):

  ```
  [ENTRYPOINT.environment] WARNING: A custom 'step.d/015-image-vars.sh' was found in this image. The step no longer exists in the base images — its role moved to 'container/entrypoint/image-env.sh'. It keeps working (sourced by the environment orchestrator, step.d/015-environment.sh) until 2027-11-17, afterwards it will be silently ignored. Move the logic into image-env.sh.
  Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-17-environment-pipeline.md
  ```

- Boot logs now contain the orchestrator's own lines (`[ENTRYPOINT.environment] Configuring the environment pipeline...`) and each env file is logged as before (`[ENTRYPOINT.custom-env] Loading: …`).
- When the compatibility layer expires (2027-11-17), the step-loop filter and the legacy functions disappear — overridden step files are then silently skipped by nothing (they never load at all).

## Further Reading

- [Environment Files](../common.md#environment-files) in Shared Concepts
- [Environment Variable Management](../contributing.md#4-environment-variable-management-system) in Contributing
