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

# The remap below needs a writable /etc: groupmod and usermod rewrite
# /etc/group and /etc/passwd and create lock files (/etc/group.lock, ...) next
# to them. On a read-only root filesystem (docker --read-only, Kubernetes
# readOnlyRootFilesystem) both would die with a raw "groupmod: cannot lock
# /etc/group" (exit 10) — and silently continuing would boot the container with
# the default uid/gid 33, so every user-owned file would get the wrong
# ownership. Aborting here is deliberate.
#
# The check is a "-w" test on the /etc DIRECTORY, not on the files: the lock
# files are created in /etc, so directory writability is what usermod/groupmod
# actually need. It is honest even though this runs as root: bash's "-w" uses
# access(2)-style checks that honour the read-only mount (verified: FALSE for
# root on a read-only rootfs, TRUE on a writable one), while the permission
# bits of the files themselves are meaningless for root. The existing
# _path_is_on_read_only_mount helper answers a different question (mount flags,
# for best-effort warnings) — here the honest question is "can the remap
# write", and the -w test answers exactly that.
#
# Deliberately placed AFTER the "already set to target values" skip above:
# PUID/PGID requesting the default 33/33 needs no write at all, so such boots
# keep working on read-only roots (the documented read-only support).
if [ ! -w "/etc" ]; then
  echo "[ENTRYPOINT.user-setup] Error: PUID/PGID are not supported with a read-only root filesystem (cannot update /etc/passwd and /etc/group). Aborting." >&2
  exit 1
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
