#!/bin/bash
echo "[ENTRYPOINT.php] Configuring PHP";

VARS_TO_SUBSTITUTE='$PHP_TIMEZONE $PHP_MEMORY_LIMIT $PHP_UPLOAD_MAX_FILESIZE $PHP_POST_MAX_SIZE'
envsubst "$VARS_TO_SUBSTITUTE" < /etc/app/config.tpl/php/php.common.tpl.ini > /usr/local/etc/php/conf.d/zzz.app.common.ini

VARS_TO_SUBSTITUTE='$PHP_PROD_DISPLAY_ERRORS $PHP_PROD_DISPLAY_STARTUP_ERRORS'
envsubst "$VARS_TO_SUBSTITUTE" < /etc/app/config.tpl/php/php.prod.tpl.ini > /usr/local/etc/php/conf.d/zzz.app.prod.ini

VARS_TO_SUBSTITUTE='$PHP_FPM_MAX_CHILDREN $PHP_FPM_START_SERVERS $PHP_FPM_MIN_SPARE_SERVERS $PHP_FPM_MAX_SPARE_SERVERS $PHP_FPM_MAX_REQUESTS'
envsubst "$VARS_TO_SUBSTITUTE" < /etc/app/config.tpl/php/fpm-pool.tpl.conf > /usr/local/etc/php-fpm.d/www.conf

echo "[ENTRYPOINT.php] PHP configuration completed";
