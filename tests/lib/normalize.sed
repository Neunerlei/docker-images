# normalize.sed — the ONLY place where volatile values are normalized.
#
# Everything the capture records is diffed byte-for-byte EXCEPT what this file
# matches. Every entry must carry a comment saying WHY the value is volatile
# and what class of difference it legitimately hides. Do not add entries to
# make a diff disappear — if a diff shows a real behavior change, it belongs
# in the review, not in this file. (Plan: docs/proposals/2026-11-12-test-
# suite-implementation-plan.md §2.4.)
#
# Applied by lib/capture.sh to every section file of a capture, and to the
# recorded goldens at --update time, so both sides of every diff went through
# the same pass.

# --- Build-mode marker timestamp --------------------------------------------
# The marker written in CONTAINER_MODE=build ("init-build-env") embeds the UTC
# time of the build-mode run. Not produced by the nginx scenarios below (they
# never enter build mode), but kept here so a build-mode scenario cannot
# forget it. Only the marker line is matched — nothing else.
s/^Build mode run finished at: .*$/Build mode run finished at: <NL-TEST-TIMESTAMP>/

# --- Auto-detected NGINX resolver -------------------------------------------
# The resolver is read from /etc/resolv.conf on every boot (entrypoint
# common-env.sh): 127.0.0.11 on user-defined Docker networks, the host
# resolver on the default bridge (Docker copies resolv.conf there), the
# cluster DNS in Kubernetes. The VALUE depends on the machine that runs the
# suite — two captures of the SAME image on different networks legitimately
# differ — so it is normalized by CONTEXT, not by address: an entry that
# matches only "127.0.0.11" would normalize one side of a diff and not the
# other. The structural differences (snippet comments, valid=/timeout values,
# whether the NGINX_RESOLVER variables exist at all) stay fully visible.
# The hardcoded "127.0.0.11" inside the template's comment text is NOT
# normalized: it is baked template content, identical on every run — if a
# change edits that text, the diff must show it.
# Quoted form (the "- Exporting variable: NGINX_RESOLVER=" boot log line):
s/NGINX_RESOLVER="[^"]*"/NGINX_RESOLVER="<NL-TEST-RESOLVER>"/g
# The vars.sh snapshot export line: normalize the WHOLE value. A multi-server
# explicit NGINX_RESOLVER (the resolver-explicit scenario) would otherwise be
# half-normalized by the token rule below, leaving later list members
# dangling — the resolver DIRECTIVE in nginx-T.conf stays the observable for
# the actual server list:
s/^export NGINX_RESOLVER=.*/export NGINX_RESOLVER=<NL-TEST-RESOLVER>/
# Unquoted form (any other NGINX_RESOLVER= token); runs after the two rules
# above, so both collapse to the same normalized shape:
s/NGINX_RESOLVER=[^ \t;]*/NGINX_RESOLVER=<NL-TEST-RESOLVER>/g
# The nginx resolver directive, IPv4 and bracketed-IPv6 forms (the address
# characters only, up to " valid=" — a resolver LIST with several servers
# would need its own entry; none of our images produce one today):
s/resolver [0-9.]\{7,\} valid=/resolver <NL-TEST-RESOLVER> valid=/g
s/resolver \[[0-9A-Fa-f:]\{2,\}\] valid=/resolver <NL-TEST-RESOLVER> valid=/g

# --- Salted basic-auth password hashes ---------------------------------------
# write_basic_auth_file (util.d/basic-auth.sh) hashes passwords with
# `openssl passwd -apr1`, which derives a RANDOM 8-char salt on every boot —
# the hash differs run-over-run for the same password. The hash FORMAT
# ($apr1$salt$digest, fixed length) and the user list stay visible; whether a
# given password actually works is asserted in Tier 1/3 with
# `openssl passwd -apr1 -salt`, never in the golden.
s/[$]apr1[$][./A-Za-z0-9]\{8\}[$][./A-Za-z0-9]\{22\}/<NL-TEST-APR1-HASH>/g

# --- Process identifiers ------------------------------------------------------
# PIDs are kernel scheduling outcomes — different on every boot. Normalized
# per context (not one blanket number rule) so an unrelated number can never
# be silently rewritten.

# supervisorctl status lines: "<program> RUNNING pid 12, uptime 0:00:04".
# The uptime is measured from the process start — volatile by definition.
s/pid [0-9][0-9]*, uptime [0-9][0-9]*:[0-9][0-9]*:[0-9][0-9]*/pid <NL-TEST-PID>, uptime <NL-TEST-UPTIME>/g

# supervisord startup log ("spawned: 'nginx' with pid 12"). Not produced by
# the current nginx scenarios (supervisord logs to /dev/null), kept so a
# logging-supervisor change cannot leak raw PIDs into a diff unnoticed.
s/with pid [0-9][0-9]*/with pid <NL-TEST-PID>/g

# nginx error-log notices ("start worker process 12"). These DO reach the
# live logs section: nginx error_log goes to stderr.
s/start worker process [0-9][0-9]*/start worker process <NL-TEST-PID>/g

# --- Timestamps in live logs ---------------------------------------------------
# Only the live capture has a wall-clock-linked stream (docker logs); the
# entrypoint boot log itself carries no timestamps.

# nginx error-log line prefix: "2026/11/12 10:11:12 [notice] 12#12: ...".
s/^[0-9][0-9][0-9][0-9]\/[0-9][0-9]\/[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] /<NL-TEST-TIMESTAMP> /

# nginx error-log "pid#connection-counter" token right after the level —
# both fields are per-process volatile.
s/[0-9][0-9]*#[0-9][0-9]*: /<NL-TEST-PID>#<NL-TEST-CONNECTION>: /g

# nginx access-log timestamp ($time_local in the main_timed format):
# "[12/Nov/2026:10:11:12 +0000]".
s/\[[0-9][0-9]\/[A-Za-z][A-Za-z][A-Za-z]\/[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9]:[0-9][0-9] [+-][0-9][0-9][0-9][0-9]\]/[<NL-TEST-TIMESTAMP>]/g

# nginx access-log timing tail ($body_bytes_sent $request_time ...): the
# status, request and address stay, the byte count and the float request
# timing are machine-speed dependent.
s/^\([0-9.][0-9.]* - [^ ]* \[[^]]*\] "[^"]*" [0-9][0-9][0-9]\) .*$/\1 <NL-TEST-REQUEST-TIMING>/

# supervisord's own activity log reaches the live logs section (supervisord
# logs to stderr in addition to its logfile even in nodaemon mode): every
# line is prefixed "2026-11-12 18:42:01,255 " — wall clock, volatile.
s/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9][0-9][0-9] /<NL-TEST-TIMESTAMP> /

# Supervisor tempfile names under childlogdir (/run): the runtime creates
# "<program>-stdout---supervisor-<random 8 chars>.log" per redirected process
# (the crash-on-fatal eventlistener's stdout capture shows up in the
# ownership find). The suffix is a mktemp-style random string, different on
# every boot; the program name and the file's presence/mode stay visible.
s/---supervisor-[A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-]\.log/---supervisor-<NL-TEST-RANDOM>.log/g

# --- Container ID / hostname ----------------------------------------------------
# Docker names a container after its (random) ID unless --hostname is given,
# so any captured value that embeds it changes every run. No current section
# embeds a hostname — this entry exists so the day one starts doing so (e.g.
# a prompt or a rendered template gaining $HOSTNAME), the capture fails the
# run-over-run determinism check ONCE, with this entry as the ready-made,
# honest fix instead of an undocumented sed elsewhere. Deliberately narrow:
# a line that is ONLY 12 hex chars (checksum lines are "hash  path", and are
# 32 chars — they do not match).
/^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/s/.*/<NL-TEST-CONTAINER-ID>/

# --- Self-signed certificate material -------------------------------------------
# _process_ssl_cert_templates (step.d/020-nginx.sh) generates a fresh RSA key
# and self-signed certificate on every boot when no custom certs are mounted:
# key/PEM bodies, serial numbers, fingerprints and validity dates are random
# per boot. The https scenarios (plan §5) will exercise this path; the two
# checkpoint scenarios (plain HTTP) produce no certificate output today, so
# these entries are intentionally narrow and inert until then:
# content lines inside PEM blocks (between BEGIN/END markers),
/-----BEGIN /,/-----END /s/^[A-Za-z0-9+/]\{1,\}=*$/<NL-TEST-CERT-MATERIAL>/
# and the fingerprint/serial lines of an `openssl x509` style dump.
s/^[A-Za-z0-9]* [Ff]ingerprint=.*$/<NL-TEST-CERT-FINGERPRINT>/
s/^\([ \t]*Serial Number:\) .*$/\1 <NL-TEST-CERT-SERIAL>/

# --- Work-data checksums of per-boot generated certificates ----------------------
# The https scenario's work-data.checksums lists md5sum lines for cert.pem and
# key.pem under the rendered work data — the HASH of freshly generated
# certificate material is random on every boot (the same volatility class as
# the PEM bodies above). Only the checksum is normalized; the PATH stays
# visible, so a change in WHERE the certificates are rendered still diffs.
/cert\.pem$/s/^[0-9a-f][0-9a-f]* /<NL-TEST-CERT-CHECKSUM> /
/key\.pem$/s/^[0-9a-f][0-9a-f]* /<NL-TEST-CERT-CHECKSUM> /

# --- openssl key-generation progress ---------------------------------------------
# The self-signed certificate generation (openssl req -newkey rsa:2048) prints
# its random prime-hunting progress to stderr while it runs: lines made only of
# dots, plus signs and asterisks — different on every boot. The "--" separator
# lines around them are constant and stay visible.
/^[.+*][.+*][.+*][.+*][.+*][.+*][.+*][.+*][.+*]*$/s/.*/<NL-TEST-CERT-KEYGEN-PROGRESS>/

# --- Gunicorn runtime identifiers --------------------------------------------------
# python-nginx live captures: gunicorn logs its own process identity to
# stderr — "Listening at: unix:///run/gunicorn.sock (12)" (the master pid in
# parentheses) and "Booting worker with pid: 23". Kernel scheduling outcomes,
# normalized like the other PID classes above; the socket path and message
# text stay visible.
s/Listening at: \(.*\) ([0-9][0-9]*)/Listening at: \1 (<NL-TEST-PID>)/g
s/Booting worker with pid: [0-9][0-9]*/Booting worker with pid: <NL-TEST-PID>/g
# Gunicorn's log-line prefix "[2026-11-12 20:06:01 +0000] [396] [INFO] ":
# wall-clock timestamp plus the MASTER pid in brackets, both volatile. The
# level and message stay visible.
s/^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [+-][0-9][0-9][0-9][0-9]\] \[[0-9][0-9]*\] /[<NL-TEST-TIMESTAMP>] [<NL-TEST-PID>] /

# --- php-fpm log timestamps ---------------------------------------------------------
# php-nginx live captures: php-fpm logs NOTICE/WARNING lines to stderr in the
# format "[12-Nov-2026 10:11:12] NOTICE: ..." — wall clock plus the fpm master
# pid, both volatile. The level and message stay visible.
s/^\[[0-9][0-9]-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] /[<NL-TEST-TIMESTAMP>] /
# The master pid inside the fpm startup notice:
s/NOTICE: fpm is running, pid [0-9][0-9]*/NOTICE: fpm is running, pid <NL-TEST-PID>/
# php-fpm access log ("catch_workers_output" style, reaches logs-stderr): the
# request timestamp uses its own format ("- -  12/Nov/2026:19:37:47 +0000"),
# not the nginx main_timed line matched above — normalized here. Path, status
# and the deterministic request SET (readiness poll + http-probes) stay.
s/^- -  [0-9][0-9]\/[A-Za-z][A-Za-z][A-Za-z]\/[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9]:[0-9][0-9] [+-][0-9][0-9][0-9][0-9] /- -  [<NL-TEST-TIMESTAMP>] /

# --- Ordering of inherently unordered output -------------------------------------
# NOT handled here on purpose: unordered output (the container-vars snapshot,
# find listings, checksum lists, supervisor conf.d files) is SORTED at its
# source in lib/probe.sh before it is written ("sort before writing", plan
# §2.4). Normalizing order in sed would run after section splitting, where
# the diff has already happened.
