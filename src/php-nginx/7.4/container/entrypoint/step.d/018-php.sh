#!/bin/bash
echo "[ENTRYPOINT.php] Configuring PHP";

process_tpl "php-ini"
process_tpl "php-fpm"

echo "[ENTRYPOINT.php] PHP configuration completed";
