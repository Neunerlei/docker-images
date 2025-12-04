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

declare current_uid="$(id -u www-data)"
declare current_gid="$(id -g www-data)"
declare target_uid="${PUID:-${current_uid}}"
declare target_gid="${PGID:-$current_gid}"

if [ "${target_uid}" == "${current_uid}" ] && [ "${target_gid}" == "${current_gid}" ]; then
  echo "[ENTRYPOINT.user-setup] User and group ID already set to target values, skipping user configuration."
  return;
fi

echo "[ENTRYPOINT.user-setup] Current www-data UID/GID is ${current_uid}/${current_gid}. Target is ${target_uid}/${target_gid}."

# Change the group ID first
if [ "${target_gid}" != "${current_gid}" ]; then
  if [ "$(getent group "${target_gid}")" ]; then
    existing_group_name=$(getent group "${target_gid}" | cut -d: -f1)
    echo "[ENTRYPOINT.user-setup] WARNING: GID ${target_gid} is already in use by group '${existing_group_name}'. This may cause conflicts."
  fi
  groupmod -o -g "${target_gid}" www-data
fi

# Change the user ID
if [ "${target_uid}" != "${current_uid}" ]; then
  if id -u "${target_uid}" >/dev/null 2>&1; then
    existing_user_name=$(getent passwd "${target_uid}" | cut -d: -f1)
    echo "[ENTRYPOINT.user-setup] WARNING: UID ${target_uid} is already in use by user '${existing_user_name}'. This may cause conflicts."
  fi
  usermod -o -u "${target_uid}" www-data
fi
