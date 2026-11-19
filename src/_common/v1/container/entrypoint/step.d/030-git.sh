# When using composer/npm in a development environment, it can be the case that the project directory is owned by a different user than www-data, which can cause issues with git commands.
# To avoid warnings about unsafe directories, we simply add the project directory to the list of safe directories in git configuration when in development environment.
# In a production environment, this is a security risk and should not be done, because it allows any user to execute git commands in the project directory,
# which can lead to potential security vulnerabilities if the project directory is owned by a different user than www-data.
# The setting exists because of CVE-2022-24765  https://nvd.nist.gov/vuln/detail/cve-2022-24765 but in a development environment,
# it is often the case that the project directory is owned by a different user than www-data,
# which can cause issues with git commands if the directory is not added to the list of safe directories.
# So the bottom line: Okay for development, not okay for production.
# I also opted not to use this in a "build" environment, because in a build environment,
# we should ensure that the project directory is owned by www-data to avoid any issues with git commands.
# NOTE: find_environment() normalizes ENVIRONMENT to "development"/"production" —
# accept both the normalized value and the short form.
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "development" ]]; then
    echo "[ENTRYPOINT] Setting up Git configuration for development environment..."
    # Guard the --add calls: --add appends, and the www-data home may persist
    # on a named volume mounted at /container/work — without the check the
    # safe.directory entry would grow on every boot.
    # Both calls are best-effort: on read-only filesystems the config file
    # location may not be writable (/root for the root call, the www-data home
    # on a read-only /container/work). A missing safe.directory entry only
    # produces git warnings, so we warn and continue instead of aborting.
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx /var/www/html; then
        if ! git config --global --add safe.directory /var/www/html 2>/dev/null; then
            echo "[ENTRYPOINT] Warning: could not add /var/www/html to root's git safe.directory (read-only filesystem?). Continuing." >&2
        fi
    fi
    if ! gosu www-data git config --global --get-all safe.directory 2>/dev/null | grep -qx /var/www/html; then
        if ! gosu www-data git config --global --add safe.directory /var/www/html 2>/dev/null; then
            echo "[ENTRYPOINT] Warning: could not add /var/www/html to www-data's git safe.directory (read-only filesystem?). Continuing." >&2
        fi
    fi
fi
