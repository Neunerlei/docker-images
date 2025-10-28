#!/bin/bash
# This allows the final image to hook in it's own script files
if [ -f /usr/bin/app/entrypoint.local.sh ]; then
	source /usr/bin/app/entrypoint.local.sh;
fi

bash -c "${*}"
