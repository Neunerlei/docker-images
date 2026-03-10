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
if [[ "$ENVIRONMENT" == "dev" ]]; then
    echo "[ENTRYPOINT] Setting up Git configuration for development environment..."
    git config --global --add safe.directory /var/www/html
fi
