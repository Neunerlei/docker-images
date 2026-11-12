# Migration Guide: Build Mode Marker and Variables for Later `RUN` Steps

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: the legacy build mode invocation (running the entrypoint without a command). The layer will be present until **2027-11-12**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

**New build command:** `init-build-env` is now the supported way to run build mode in a Dockerfile `RUN`. It performs the full entrypoint bootstrap and writes a marker file, `/container/build-mode.marker`, into the image. Booting an image that contains the marker aborts with `exit 1` and an explanatory error before the entrypoint changes anything — for images built with `init-build-env`, refusing to boot is the expected behavior, not an accident. For builder stages that must remain bootable (e.g. CI test stages), `init-build-env --allow-boot` runs the same build mode without writing the marker.

**Why the marker exists:** before this release, an image could run the entrypoint without a command in its final stage and be booted — and that worked. This release introduces the new work-data model: every boot resets `work/data` from the pristine build-time staging area. For an image whose final stage ran build mode, that reset would silently discard the changes made by later build steps, with no error anywhere. Since the new model makes that state unbootable-by-design, images built the new way refuse to start loudly instead of losing data quietly.

**Fixed:** later `RUN` steps in a builder stage receive the container variables again, as the documentation has always promised. A previous change overwrote `container-vars.sh` with `export -p` and then deleted it at the end of a build-mode run, so separate `RUN` steps (`RUN pnpm build`, `RUN composer install --no-dev`) ran without `NODE_ENV`, `DOCKER_SERVICE_ABS_PATH` and the other derived variables. The fix applies to both the new and the legacy invocation.

## Who Is Affected

- **Consumers using the legacy invocation** (`RUN /container/entrypoint/entrypoint.sh` without a command, or `RUN source /container/entrypoint/entrypoint.sh && …`): these keep working — no marker is written, the image stays bootable — but every build-mode run logs a deprecation warning pointing here. The compatibility layer restores the **original behavior**: writes into the work data (`/container/work/data`) made by `RUN` steps after the build-mode run **survive boots**, because the run syncs the work data back into the pristine staging area and restores the build-time symlink — the same effect images had before the work-data model by having no reset at all. As before, build-time rendered configuration (including anything rendered from build-time environment values) becomes part of the image — don't render secrets at build time.
- **Consumers that migrate to `init-build-env`:** their builder-stage images refuse to boot — by design. Copy the artifacts into a fresh final stage instead.
- **CI pipelines that start a builder-stage image to run tests** (`docker build --target builder` + `docker run … phpunit`): with `init-build-env` these fail now; build the stage with `init-build-env --allow-boot` instead (see below). (Builder stages still using the legacy invocation keep starting, with the deprecation warning.)

## What to Do

### Switch to `init-build-env` (recommended)

```dockerfile
FROM neunerlei/php-nginx:latest AS builder
COPY --chown=www-data:www-data ./src ./src
RUN init-build-env
RUN composer install --no-dev --optimize-autoloader

FROM neunerlei/php-nginx:latest
COPY --from=builder /var/www/html ./
```

### Starting a builder-stage image anyway (CI)

Build the stage with the opt-out flag — no marker is written, the image can boot:

```dockerfile
FROM neunerlei/php-nginx:latest AS builder
COPY --chown=www-data:www-data ./src ./src
RUN init-build-env --allow-boot
RUN composer install --no-dev --optimize-autoloader
```

Changes made by later `RUN` steps (e.g. a `docker-php-ext-enable` dropping a conf.d file) **survive boots**: the rendered work data is synced back into the staging area. Caveat: build-time rendered configuration — including anything rendered from build-time env values — becomes part of the image, so don't render secrets at build time. (Last-resort escape hatch when the Dockerfile can't be changed: `docker run --entrypoint …` bypasses the entrypoint entirely.)

## Notes

- The marker lives in the image layer (like the work-data staging area), so mounting `/container/work` (tmpfs, `emptyDir`, a named volume) cannot hide it.
- Running `init-build-env` (with or without `--allow-boot`) multiple times in the same stage keeps working; the marker is simply rewritten or stays absent. The legacy invocation works the same way.
- The variables are a **snapshot** taken at the build-mode run. It takes precedence over `ENV` lines declared *after* it — declare all `ENV` lines before `init-build-env`; to re-run after changing `ENV`, use the exec form `RUN ["init-build-env"]` (the shell form goes through the bash wrapper, which sources the old snapshot and would override the new `ENV`).
- Run build commands in a **separate `RUN`** after `init-build-env`. Chaining in the same line (`RUN init-build-env && npm run build`) only gives the variables to env-wrapped child processes — the outer shell started before the snapshot existed. This also applies to the legacy `source …entrypoint.sh && …` pattern's migration: don't translate it one-to-one.
- Shell-form `RUN` receives the variables via the bash wrapper (`/bin/sh` → wrapper → `container-vars.sh`); exec-form `RUN ["…"]` only through the env-wrapped binaries (`node`, `python`, `pip`, `php`, …).
- Builder images pushed to a registry (e.g. as a CI cache) contain the derived variables, including everything computed by `custom/env` files — do not pull secrets in at build time.

## Further Reading

- [Build Mode](../common.md#build-mode) in the shared documentation
