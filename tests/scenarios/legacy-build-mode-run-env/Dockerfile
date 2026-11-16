# Build-time scenario (plan §2.3): built ON TOP of the image under test.
#
# The build-mode run's own output is captured into the work directory so the
# boot-time `cat` command can report it (the deprecation warning is a BUILD
# log line — redirecting it into a surviving file is the only way a boot
# capture can observe it). Output redirection does not change the run's exit
# code semantics.
ARG BASE
FROM ${BASE}

RUN /container/entrypoint/entrypoint.sh > /container/work/build-log.txt 2>&1

RUN env > /out
