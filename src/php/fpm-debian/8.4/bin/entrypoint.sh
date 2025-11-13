#!/bin/bash
# This allows the final image to hook in it's own script files
if [ -f /usr/bin/app/entrypoint.local.sh ]; then
	source /usr/bin/app/entrypoint.local.sh;
fi

# For legacy reasons I still support the "/user" variants of the entrypoint, too.
# @todo remove this in v8.5
# DO not rely on this being present, it is only for legacy reasons!
if [ -f /user/bin/app/entrypoint.local.sh ]; then
  echo "WARNING: The entrypoint file '/user/bin/app/entrypoint.local.sh' is deprecated and will be removed in v8.5! Please use '/usr/bin/app/entrypoint.local.sh' instead!";
	source /user/bin/app/entrypoint.local.sh;
fi

bash -c "${*}"
