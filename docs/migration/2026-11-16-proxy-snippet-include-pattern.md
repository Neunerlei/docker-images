# Migration Guide: Proxy Snippet Include Pattern

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: a boot-time warning for proxy snippets named the legacy way. The layer will be present until **2027-11-16**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

The include pattern for per-service custom snippets in proxy mode (`docker/custom/nginx/proxy/`) changed from `<key>*.conf` to `<key>.<name>.conf` — **a dot is now required after the service key**. A file named exactly `<key>.conf` (e.g. `api.conf`) keeps working for backward compatibility.

The reason is prefix collisions: the old pattern (`api*.conf`) globbed across the key boundary, so the keys `api` and `api_v2` included each other's snippets — `api_v2.rewrite.conf` landed in the `api` location and `api.cache.conf` in the `api_v2` location. With the dotted pattern, the dot after the key is the key boundary: `api.cache.conf` belongs to `api`, `api_v2.cache.conf` to `api_v2`, and never to both.

The catch: files that only the **old** pattern matched — `<key>-something.conf` or `<key>something.conf`, e.g. `api-cors.conf` or `apicache.conf` — are **not included anymore**. Previously such a file would have been dropped silently: no error, no configuration, just a missing snippet. The compatibility layer closes that gap for the transition period: while the proxy locations are rendered, the entrypoint warns loudly for every such file, naming the file and the scheme it must be renamed to. Files that belong to another configured key whose name merely shares the prefix (e.g. `api_v2.rewrite.conf` when scanning for key `api`) are skipped by the check — they are included by their own key's pattern and are not dropped.

## Who Is Affected

- **Consumers with custom proxy snippets named `<key>-something.conf` or `<key>something.conf`** — e.g. `api-cors.conf`, `apicache.conf`, `frontend-headers.conf` — for a service defined with `PROXY_<KEY>_CONTAINER`. These snippets are no longer included; the affected location silently loses the configuration they carried.
- **Consumers whose snippets are named `<key>.<name>.conf`** (e.g. `api.cache.conf`) **or exactly `<key>.conf`** are not affected — both keep working unchanged.
- Only the nginx image's proxy mode has per-service snippet directories; static mode and the runtime images (`nginx/location/`, `nginx/global/`) are unaffected.

## What to Do

Rename the snippet so the key is followed by a dot:

```
docker/custom/nginx/proxy/
├── api-cors.conf     →  api.cors.conf
├── apicache.conf     →  api.cache.conf
└── api.conf          →  (unchanged — the exact <key>.conf form still works)
```

Markers keep working as before: `api.cors.prod.https.conf` loads only when the marker conditions are met.

If you do nothing, every boot prints this warning until the compatibility layer expires:

```
[ENTRYPOINT.proxy] WARNING: Custom proxy snippet 'api-cors.conf' for service 'api' is NOT included anymore: the include pattern changed from '<key>*.conf' to '<key>.<name>.conf' (dot required after the key; a file named exactly '<key>.conf' still works). Rename the snippet or it will be silently ignored.
Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-16-proxy-snippet-include-pattern.md
```

## Notes

- The snippet ownership check for [basic auth](../common.md#basic-authentication) uses the same pattern: a proxy snippet manages a location's authentication only if the include actually picks it up. A legacy-named file is no longer included, so it drops out of the check on both sides: it does not take ownership (its `auth_basic` directive is invisible — the entrypoint renders its generated directives and the location stays protected by them), and it can no longer collide with those generated directives either (NGINX never sees the two `auth_basic` declarations in one context, so the duplicate-directive abort cannot happen).
- When the compatibility layer expires (2027-11-16), the warning disappears — the affected files stay un-included, without a message.

## Further Reading

- [Per-Service Snippets (Proxy Mode Only)](../nginx.md#12-per-service-snippets-proxy-mode-only-marker-aware-templates) in the nginx documentation
