# Build-time scenario (plan §2.3): built ON TOP of the image under test.
#
# The LEGACY invocation: running the entrypoint WITHOUT a command was the only
# way builds worked before the branch's build-mode marker — it must keep
# working (deprecated compatibility layer, expires 2027-11-12): everything
# runs, no marker, image stays bootable, later RUN steps keep their changes.
#
# The later RUN writes into the work DIRECTORY (not work/data): that path
# exists on both trees during the build — on main there is no work/data at
# all, and a data-path write would fail the main build for the wrong reason.
# Parity facts (both verified): the branch keeps the marker across the boot
# (its reset scope is exactly work/data; the marker sits outside it), while
# MAIN LOSES it — main's build-mode run already created the clean-state
# snapshot during the build, so the boot reset (whole work dir except the
# snapshot) wipes a later-RUN write. The branch therefore preserves MORE than
# main on this path — expected-diffs #13. Survival of work/DATA writes (the
# mechanism the migration guide actually promises) is covered by
# init-build-env-allow-boot on the branch side.
ARG BASE
FROM ${BASE}

RUN /container/entrypoint/entrypoint.sh

RUN touch /container/work/build-step-marker
