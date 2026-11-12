# Migration Guide: Exact Command Arguments

> **Compatibility layer:** Since the images are bound to the software version they contain, breaking changes can not be introduced easily. Therefore we provide an internal compatibility layer for this migration — here: the single-string command fallback. The layer will be present until **2027-11-12**. After that point, it may be removed at any time, leading to potential failures/unwanted behaviour — so ensure to upgrade your configuration until then.

## What Changed

The entrypoint used to join the command arguments into a single string and word-split it again at execution time. That destroyed argument boundaries: `docker run <image> sh -c 'echo A; echo B'` silently ran nothing (and could even exit 0), because the `-c` payload lost its quoting.

Commands are now executed with `exec "${entrypoint_command[@]}"` — the argument boundaries Docker passes are preserved exactly.

## Who Is Affected

- **Consumers passing the command as a single string** — e.g. compose `command: ["npm run dev"]` (single-element list) or Kubernetes `args: ["php artisan queue:work"]`. These only ever worked because of the old word-splitting; they now run through a deprecation fallback.
- **Custom entrypoint scripts** reading `$entrypoint_command` — it is now an array.

## What to Do

### Single-string commands

The fallback splits the string on whitespace (including newlines) and logs a deprecation warning, but **will be removed in a future release**. Pass commands as separate arguments instead:

```yaml
command: ["npm", "run", "dev"]
```

Note the fallback reproduces word splitting only — embedded quotes (`["sh -c 'echo hi'"]`) stay broken as they were before. Use separate arguments for anything quoted.

### Custom entrypoint scripts

If you read `$entrypoint_command` in a script under `/container/custom/entrypoint/`, treat it as an array (`"${entrypoint_command[@]}"`). Reassigning a plain string to it now only overwrites the first element.
