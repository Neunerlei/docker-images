ARG BASE
FROM ${BASE}

# First build-mode run (writes the build-mode marker, renders the work data,
# and — since the plain-run sync fix — syncs it back into the staging area
# and restores the build-time symlink).
RUN init-build-env

# A separate later RUN step writes into the work data. After the first run
# the work data is the staging symlink again, so this file lands in the
# STAGING area — the place every further run and boot restores from.
RUN touch /container/work/data/double-run-marker

# Second build-mode run: must keep working (the documented "repeated runs
# keep working" contract), sync the rendered state (including the marker)
# back into staging, and --allow-boot additionally removes the marker an
# earlier plain run wrote, so the image stays bootable and the boot below
# can prove the full chain end to end.
RUN init-build-env --allow-boot

# Build-time proof that the marker survived the second build-mode run: with
# the sync-back in place the work data is the staging link again and the
# marker is reachable through it; without the sync this RUN fails the
# scenario build loudly.
RUN test -f /container/work/data/double-run-marker
