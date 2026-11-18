# Build-time scenario: the downstream override is COPYied into the image's
# step.d (COPY container /container overlays the common layer).
ARG BASE
FROM ${BASE}
COPY files/015-image-vars.sh /container/entrypoint/step.d/015-image-vars.sh
