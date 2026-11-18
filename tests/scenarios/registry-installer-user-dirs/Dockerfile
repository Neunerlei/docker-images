# Build-time scenario: break the ownership the installer established at
# BUILD time, so the boot is the only thing that can repair it. A boot
# without the installer's registry entries (the regression this pins: a
# plain reassignment in step 070 dropping them) leaves the directories
# root-owned and the assertion fails. The per-path guards keep the same
# Dockerfile valid for both images of the scenario (each image has only one
# of the two directories).
ARG BASE
FROM ${BASE}
RUN chown -R root:root /opt/venv 2>/dev/null || true
RUN chown -R root:root /usr/local/lib/node_modules 2>/dev/null || true
