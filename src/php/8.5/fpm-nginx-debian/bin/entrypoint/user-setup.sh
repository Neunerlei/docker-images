#!/bin/bash

# This allows the final image to set up a custom user setup script
if [ -f /usr/bin/app/entrypoint.user-setup.sh ]; then
  echo "[ENTRYPOINT.user-setup] Executing custom user setup script '/usr/bin/app/entrypoint.user-setup.sh'";
	source /usr/bin/app/entrypoint.user-setup.sh;
fi
