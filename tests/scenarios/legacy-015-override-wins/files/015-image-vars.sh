# A downstream image's modified copy of the OLD php-nginx 015-image-vars.sh
# (pre-2026-11-17 shape): different memory limit, forced worker mode. The
# marker echo lets the tests assert the file ran EXACTLY once.
echo "[LEGACY-015-OVERRIDE] running"

# Downstream tuning: a different memory limit than the base default
export PHP_MEMORY_LIMIT="256M"

# Downstream decision: this image is always a worker
export PHP_WORKER_COMMAND="php -r 'while (true) { sleep(1); }'"

if [ -z "${CONTAINER_MODE}" ] ; then
  if [ -n "${PHP_WORKER_COMMAND}" ]; then
    export CONTAINER_MODE="worker"
  else
    export CONTAINER_MODE="web"
    feature_registry="${feature_registry} nginx"
  fi

  # Ensure supervisor is always enabled
  feature_registry="${feature_registry} supervisor"
fi
