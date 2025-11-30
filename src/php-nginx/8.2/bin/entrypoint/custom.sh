#!/bin/bash

# This allows the final image to hook in it's own script files
if [ -f "${CONTAINER_BIN_DIR}/entrypoint.local.sh" ]; then
  echo "[ENTRYPOINT.custom] Executing custom entrypoint script '${CONTAINER_BIN_DIR}/entrypoint.local.sh'";
	source "${CONTAINER_BIN_DIR}/entrypoint.local.sh";
fi
