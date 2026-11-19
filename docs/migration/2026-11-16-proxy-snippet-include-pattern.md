# Migration Guide: Proxy Snippet Include Pattern

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: the original include behavior stays fully intact. Every snippet the old pattern matched is still included (rendered under a `<key>.legacy.<name>.conf` bridge name), with a boot-time warning for each file that relies on it. If you want the container to refuse legacy names instead, set `LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true` (see [Opting Into the New Behavior Early](#opting-into-the-new-behavior-early)). The layer will be present until **2027-11-16**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

The include pattern for per-service custom snippets in proxy mode (`docker/custom/nginx/proxy/`) changed from `<key>*.conf` to `<key>.<name>.conf` — **a dot is now required after the service key**. A file named exactly `<key>.conf` (e.g. `api.conf`) keeps working for backward compatibility.

The reason is prefix collisions: the old pattern (`api*.conf`) globbed across the key boundary, so the keys `api` and `api_v2` included each other's snippets — `api_v2.rewrite.conf` landed in the `api` location and `api.cache.conf` in the `api_v2` location. With the dotted pattern, the dot after the key is the key boundary: `api.cache.conf` belongs to `api`, `api_v2.cache.conf` to `api_v2`, and never to both.

Files that only the **old** pattern matched — `<key>-something.conf` or `<key>something.conf`, e.g. `api-cors.conf` or `apicache.conf` — do not match the new pattern. For the transition period, the compatibility layer restores their inclusion: while the proxy locations are rendered, every file matching the old `<key>*.conf` glob that the new pattern does not already include is rendered a second time as `<key>.legacy.<name>.conf` — a name the current include glob picks up — so the snippet lands in the location exactly like before. Marker conditions keep applying to the original filename (`api-cors.prod.https.conf` still loads only when the markers are met).

The layer deliberately restores the old behavior **including its flaws**: with both `api` and `api_v2` configured, `api_v2.rewrite.conf` matches the old `api*.conf` glob — during the transition it is therefore included in **both** locations again. That prefix overlap is the very bug this migration fixes; it disappears for good when the layer expires, or immediately when you enable the strict mode below.

## Who Is Affected

- **Nobody loses configuration during the transition period.** Every snippet the old pattern included keeps working; each file that relies on the bridge prints a warning naming the file and the scheme it must be renamed to.
- **Affected at the latest by 2027-11-16:** consumers with snippets named `<key>-something.conf` or `<key>something.conf` (e.g. `api-cors.conf`, `apicache.conf`), and consumers relying on the prefix overlap (a snippet of key `api_v2` also landing in the `api` location). When the layer expires, such files are silently ignored again.
- **Consumers whose snippets are named `<key>.<name>.conf`** (e.g. `api.cache.conf`) **or exactly `<key>.conf`** are not affected at all — neither now nor after expiry.
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

If you relied on the prefix overlap (one snippet included by several prefix-sharing keys), give each key its own copy named for that key — e.g. `api.rewrite.conf` **and** `api_v2.rewrite.conf`.

## Opting Into the New Behavior Early

`LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true` disables the legacy bridge for this migration and turns legacy file names into a boot failure: the entrypoint aborts with an error for every file matching the old `<key>*.conf` glob that the current pattern does not include. This is the guarantee that a configuration renders identically before and after the layer expires — useful in CI, and the way to get the prefix-collision fix immediately instead of at expiry.

Notes on the variable:

- It is temporary: it belongs to this compatibility layer and stops working when the layer is removed after 2027-11-16 (a set variable is then simply unread). Remove it from your configuration once your snippets are renamed — or at the latest together with the layer.
- Only the exact value `true` enables strict mode; anything else (including unset) keeps the default bridging behavior.
- The check is marker-agnostic on purpose: it asserts the directory is free of legacy names for the configured keys, regardless of whether the file would be active in the current environment.

## Notes

- The default-mode warning for a bridged file looks like this (once per affected file, on every boot):

  ```
  [ENTRYPOINT.proxy] WARNING: Custom proxy snippet 'api-cors.conf' for service 'api' matches only the LEGACY include pattern '<key>*.conf' (current pattern: '<key>.<name>.conf'). It keeps working — rendered as 'api.legacy.api-cors.conf' — but only until 2027-11-16, afterwards it will be silently ignored. Rename the snippet (or give this key its own copy if you relied on the prefix overlap).
  Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-16-proxy-snippet-include-pattern.md
  ```

- The snippet ownership check for [basic auth](../common.md#basic-authentication) uses the same pattern as the include: a proxy snippet manages a location's authentication only if the include actually picks it up. While the bridge is active, a legacy-named snippet is included again — so it takes part in that check exactly like before the migration (it can take ownership with its own `auth_basic` directive, and it can collide with the generated directives, which aborts the boot rather than producing an invalid config). In strict mode the bridge is disabled and legacy files never reach the config.
- When the compatibility layer expires (2027-11-16), the bridge and the warnings disappear — the affected files stay un-included, without a message.

## Further Reading

- [Per-Service Snippets (Proxy Mode Only)](../nginx.md#12-per-service-snippets-proxy-mode-only-marker-aware-templates) in the nginx documentation
