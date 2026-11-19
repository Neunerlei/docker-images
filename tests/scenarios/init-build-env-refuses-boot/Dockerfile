# Build-time scenario (plan §2.3): the harness builds this Dockerfile ON TOP
# of the image under test (ARG BASE / FROM ${BASE}).
#
# The supported build-mode invocation: full bootstrap, services skipped, and
# the build-mode marker written into the image layer. `init-build-env` lives
# in /container/bin, which is on the image PATH — callable by name, exactly
# as the documentation shows.
ARG BASE
FROM ${BASE}

RUN init-build-env
