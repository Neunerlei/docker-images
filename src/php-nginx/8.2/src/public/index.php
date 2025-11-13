<?php
declare(strict_types=1);

if(getenv('APP_ENV') === 'prod'){
    http_response_code(404);
    echo 'There is nothing to see here. 😵‍💫';
    exit;
}

phpinfo();
