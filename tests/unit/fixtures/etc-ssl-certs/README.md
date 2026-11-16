This directory is bind-mounted READ-ONLY at /etc/ssl/certs into the Tier 1
unit-test containers (tests/run.sh, cmd_unit) so the legacy mount guard
(legacy.d/2026-02-05-migrate-to-centralized-container-dir.sh) can be exercised
against a REAL host bind mount — its `legacy_is_mounted` heuristic classifies
paths by findmnt's SOURCE shape, which only a real mount reproduces.

Hiding the CA bundle inside the unit container is harmless: unit tests make no
network use. The file below only exists so git tracks the directory; its
content is irrelevant.
