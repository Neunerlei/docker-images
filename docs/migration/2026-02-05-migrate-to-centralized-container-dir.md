# Migration Guide: Volume Mounts v2

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration. The layer will be present until **2027-02-05**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

All custom mounts now use a single directory: `/container/custom`

## Before (v1)

> "nginx" is just an example, this applies to all services that had custom mounts.

```yaml
volumes:
  - ./docker/nginx/nginx:/etc/container/templates/nginx/custom
  - ./docker/nginx/config:/etc/container/templates/php/custom
  - ./docker/certs:/etc/ssl/certs
``` 

## After (v2)

```yaml
volumes:
  - ./docker/nginx:/container/custom
```

### Special Case for SSL Certificates

Historically SSL certificates are stored in `./docker/certs` and mounted to `/etc/ssl/certs` in multiple containers.
Until our infrastructure supports the new centralized mount, you can add this as an additional mount:

```yaml
volumes:
  - ./docker/nginx:/container/custom
  - ./docker/certs:/container/custom/certs
```

> This will create a mount inside the centralized mount. Only do this if you are using SSL certificates in said container.

## How to Migrate

1. Update your `docker-compose.yml` files to use the new centralized mount.
2. Rename your existing `./docker/<service-name>` to `./docker/<service-name>_old` to keep a backup.
3. Restart your container once with `ENVIRONMENT=development` which will automatically give you a scaffolded directory structure inside `./docker/<service-name>`.

4. Move the contents of the subdirectories into the centralized directory:
    - Move all files from `./docker/<service-name>_old/nginx` to `./docker/<service-name>/nginx`
    - Move all files from `./docker/<service-name>_old/php` to `./docker/<service-name>/php`
    - Move all files from `./docker/certs` to `./docker/<service-name>/certs` (if applicable -> See Special Case for SSL Certificates)
