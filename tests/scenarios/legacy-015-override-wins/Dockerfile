# Build-time scenario: the downstream override is COPYied into the image's
# step.d — exactly how a real downstream image would ship it
# (COPY container /container overlays the common layer).
# --chmod pins the mode: COPY otherwise preserves the build context's file
# mode verbatim, which differs between checkouts (umask 002 → 664, umask 022
# → 644) and turns into a golden diff. Same rationale as the --chmod pins in
# the image Dockerfiles.
ARG BASE
FROM ${BASE}
COPY --chmod=644 files/015-image-vars.sh /container/entrypoint/step.d/015-image-vars.sh
