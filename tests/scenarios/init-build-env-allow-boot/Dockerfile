# Build-time scenario (plan §2.3): built ON TOP of the image under test.
#
# --allow-boot: build mode without the marker (the image may boot, e.g. CI
# stages). The later separate RUN writes into the work data — during the
# build, work/data is a symlink to the staging area, so the file lands where
# the boot reset restores it from: survival across the boot is the sync
# mechanism's observable.
ARG BASE
FROM ${BASE}

RUN init-build-env --allow-boot

RUN touch /container/work/data/build-step-marker
