# A downstream 015-image-vars.sh that ONLY adds an export: no mode logic, no
# features. The marker echo lets the tests assert exactly-once execution.
echo "[LEGACY-015-ADDS] running"
export MY_LEGACY_EXTRA="added-by-override"
