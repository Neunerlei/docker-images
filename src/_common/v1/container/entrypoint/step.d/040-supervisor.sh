#!/bin/bash

if [[ "${feature_registry}" == *"supervisor"* ]]; then
    echo "[ENTRYPOINT.supervisor] Configuring Supervisor..."

    process_tpl "supervisor-conf"
    process_tpl "supervisor-config"
fi
