# Migration Guide: www-data Home Directory

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: the legacy dotfile bridge from `/var/www`. The layer will be present until **2027-11-12**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

Every process running as `www-data` (gunicorn, php-fpm workers, `gosu` worker commands, wrapped CLIs like `pip`/`npm`/`composer`) now gets the writable home **`/container/work/www-data-home`** (`CONTAINER_WWW_DATA_HOME_DIR`). Previously the home resolved to `/var/www` for `gosu`/passwd-based lookups and to the unwritable `/root` for supervisor `user=` programs — libraries writing `~/` at import time (crawl4ai, huggingface, matplotlib, playwright, …) crashed.

The new home lives inside `/container/work`, so it is writable on read-only filesystems too (tmpfs/`emptyDir` mounts start empty; the entrypoint creates it). It is **not** part of the per-boot work-data reset, so caches and dotfiles survive restarts. Ownership is repaired recursively on every boot — relevant if you run with `PUID`/`PGID` and change or remove them between container recreations on a named volume.

In development containers, git's `safe.directory` for `/var/www/html` is now actually configured (the entrypoint step had a broken environment check and never ran before). This newly writes `/root/.gitconfig` and `~www-data/.gitconfig` — idempotently, and best-effort on read-only filesystems.

## Who Is Affected

- **Consumers with dotfiles under `/var/www`** (`.npmrc`, `.ssh`, `.gitconfig`, `.composer`, `.netrc`, `.local`, …) — they keep working via a symlink bridge, but should be moved.
- **Consumers mounting volumes at npm/composer cache paths** — those paths moved.
- **Consumers baking content into the www-data home at build time** — see below.

## What to Do

### Dotfiles under `/var/www`

Each dot-entry in `/var/www` that does not exist in the new home is bridged as a symlink at boot, with a deprecation warning. Move the files to `/container/work/www-data-home` — or to a persistent mount of your own — when you can. Note: writes through a bridged entry still land in `/var/www`, which is unwritable on read-only systems (unchanged behavior).

### npm / composer caches

- The npm cache moved from `/var/www/.npm` to `~www-data/.npm` inside the new home. Volumes mounted at `/var/www/.npm` no longer receive the cache — mount at the new path instead if you need a persistent cache.
- Composer (php-nginx) resolves `~` through the www-data passwd entry: cache/config (`~/.composer`, `~/.cache/composer`) moved accordingly. Explicitly set `COMPOSER_HOME`/`COMPOSER_CACHE_DIR` are unaffected.

### Build-time content in `$HOME`

Do not bake content into the www-data home at build time (`USER www-data` + `RUN playwright install`, `pip install --user`, `composer global require`): with a tmpfs/`emptyDir` at `/container/work` it is hidden at runtime, and with a named volume it is only copied on the first mount — image upgrades keep stale content (e.g. mismatched playwright browsers). Use explicit paths (`PLAYWRIGHT_BROWSERS_PATH`, `COMPOSER_HOME`, `PIP_CACHE_DIR`, …).

### Custom supervisor programs

Custom programs that use `user=www-data` should add `environment=HOME="${CONTAINER_WWW_DATA_HOME_DIR}"` to their program section — supervisor's `user=` switches only the uid. Processes launched via `gosu` (and php-fpm workers) derive `HOME` from the passwd entry automatically and need nothing.
