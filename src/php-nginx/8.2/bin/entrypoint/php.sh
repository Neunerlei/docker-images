#!/bin/bash
echo "[ENTRYPOINT.php] Configuring PHP";

render_template 'PHP_TIMEZONE PHP_MEMORY_LIMIT PHP_UPLOAD_MAX_FILESIZE PHP_POST_MAX_SIZE' /etc/app/config.tpl/php/php.common.tpl.ini /usr/local/etc/php/conf.d/zzz.app.common.ini
render_template 'PHP_PROD_DISPLAY_ERRORS PHP_PROD_DISPLAY_STARTUP_ERRORS' /etc/app/config.tpl/php/php.prod.tpl.ini /usr/local/etc/php/conf.d/zzz.app.prod.ini
render_template 'PHP_FPM_MAX_CHILDREN PHP_FPM_START_SERVERS PHP_FPM_MIN_SPARE_SERVERS PHP_FPM_MAX_SPARE_SERVERS PHP_FPM_MAX_REQUESTS' /etc/app/config.tpl/php/fpm-pool.tpl.conf /usr/local/etc/php-fpm.d/www.conf

echo "[ENTRYPOINT.php] PHP configuration completed";
