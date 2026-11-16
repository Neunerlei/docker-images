"""HOME probe served by gunicorn itself (plan §6 — /proc environ is unreadable
for uid-changed processes, so the gunicorn worker reports its own HOME).

Reported as a response header (the suite records X-Nl-Test-* headers); the
value is a path — deterministic per build."""
import os


def app(environ, start_response):
    home = os.environ.get("HOME", "(unset)")
    start_response("200 OK", [
        ("Content-Type", "text/plain"),
        ("X-Nl-Test-Home", home),
    ])
    return [b"gunicorn-home-probe-ok"]
