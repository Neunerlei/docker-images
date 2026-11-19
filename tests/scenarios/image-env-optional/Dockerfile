# Build-time scenario: remove the image's image-env.sh — the orchestrator
# must tolerate a missing file (it is optional by convention).
ARG BASE
FROM ${BASE}
RUN rm /container/entrypoint/image-env.sh
