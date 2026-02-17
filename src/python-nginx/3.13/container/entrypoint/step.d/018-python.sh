#!/bin/bash
echo "[ENTRYPOINT.python] Configuring Python (Gunicorn)";

process_tpl "gunicorn-conf"

echo "[ENTRYPOINT.python] Python (Gunicorn) configuration completed";
