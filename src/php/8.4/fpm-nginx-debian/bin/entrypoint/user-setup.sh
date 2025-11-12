#!/bin/bash

if [ -z "${PUID}" ] && [ -z "${PGID}" ]; then
    echo "[ENTRYPOINT.user-setup] User and group ID not set, skipping user configuration."
    return;
fi

if ! id -u www-data >/dev/null 2>&1; then
    echo "[ENTRYPOINT.user-setup] ERROR: User 'www-data' does not exist. This is a base image issue, that should never happen; please report!"
    exit 1
fi
if ! getent group www-data >/dev/null 2>&1; then
    echo "[ENTRYPOINT.user-setup] ERROR: Group 'www-data' does not exist. This is a base image issue, that should never happen; please report!"
    exit 1
fi

CURRENT_UID="$(id -u www-data)"
CURRENT_GID="$(id -g www-data)"
TARGET_UID="${PUID:-$CURRENT_UID}"
TARGET_GID="${PGID:-$CURRENT_GID}"

if [ "$TARGET_UID" == "$CURRENT_UID" ] && [ "$TARGET_GID" == "$CURRENT_GID" ]; then
  echo "[ENTRYPOINT.user-setup] User and group ID already set to target values, skipping user configuration."
  return;
fi

echo "[ENTRYPOINT.user-setup] Current www-data UID/GID is $CURRENT_UID/$CURRENT_GID. Target is $TARGET_UID/$TARGET_GID."

# Change the group ID first
if [ "$TARGET_GID" != "$CURRENT_GID" ]; then
  if [ "$(getent group "$TARGET_GID")" ]; then
    EXISTING_GROUP_NAME=$(getent group "$TARGET_GID" | cut -d: -f1)
    echo "[ENTRYPOINT.user-setup] WARNING: GID $TARGET_GID is already in use by group '$EXISTING_GROUP_NAME'. This may cause conflicts."
  fi
  groupmod -o -g "$TARGET_GID" www-data
fi

# Change the user ID
if [ "$TARGET_UID" != "$CURRENT_UID" ]; then
  if id -u "$TARGET_UID" >/dev/null 2>&1; then
    EXISTING_USER_NAME=$(getent passwd "$TARGET_UID" | cut -d: -f1)
    echo "[ENTRYPOINT.user-setup] WARNING: UID $TARGET_UID is already in use by user '$EXISTING_USER_NAME'. This may cause conflicts."
  fi
  usermod -o -u "$TARGET_UID" www-data
fi

# Set correct ownership on the relevant directories
echo "[ENTRYPOINT.user-setup] Setting ownership on application directories..."
chown -R www-data:www-data "/etc/app/config.tpl"
chown -R www-data:www-data "/etc/nginx/snippets/before.d"
chown -R www-data:www-data "/etc/nginx/snippets/after.d"
chown -R www-data:www-data "/usr/local/etc/php-fpm.d"
chown -R www-data:www-data "/usr/local/etc/php/conf.d"
chown -R www-data:www-data "/etc/supervisor"

# This allows the final image to set up a custom user setup script
if [ -f /usr/bin/app/entrypoint.user-setup.sh ]; then
  echo "[ENTRYPOINT.user-setup] Executing custom user setup script '/usr/bin/app/entrypoint.user-setup.sh'";
	source /usr/bin/app/entrypoint.user-setup.sh;
fi
