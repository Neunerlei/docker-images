<?php
declare(strict_types=1);

$appEnv = getenv('APP_ENV') ?: 'prod';
$info = '';
$headerClass = '';
if ($appEnv !== 'prod') {
    ob_start();
    phpinfo();
    $info = ob_get_clean();
    
    // Remove style corruptions and unnecessary elements
    $info = preg_replace(
        array(
            '/<title>.*?<\/title>/s',
            '/<meta.*?>/s',
            '/<html.*?>/s',
            '/<\/html>/s',
            '/<head.*?>(.*?)<\/head>/s',
            '/<body.*?>/s',
            '/<\/body>/s',
            '/body {.*?}/s',
            '/<hr.*?>/s'
        ),
        array(
            '',
            '',
            '',
            '',
            '$1',
            '',
            '',
            '',
            ''
        ),
        $info
    );
    $info = '<div class="php-info">' . $info . '</div>';
    
    $headerClass = ' development-mode';
}

$content = <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="ROBOTS" content="NOINDEX,NOFOLLOW,NOARCHIVE">
    <title>PHP - NGINX</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; background-color: #ffffff; padding: 20px; min-height: 100vh; }
        .container { max-width: 1200px; margin: 0 auto; padding: 0 20px; }
        .header { text-align: center; }
        .header.development-mode { margin-bottom: 3rem; padding-bottom: 2rem; border-bottom: 1px solid #e0e0e0; }
        .footer { text-align: center; margin-top: 3rem; padding-top: 2rem; border-top: 1px solid #e0e0e0; font-size: 0.9rem; color: #999; }
        .title { font-size: 2.5rem; font-weight: 600; color: #2c3e50; margin-bottom: 1rem; }
        .intro-text { font-size: 1.1rem; color: #666; max-width: 800px; margin: 0 auto; line-height: 1.7; }
        .intro-text a, .footer a { color: #71c3bb; text-decoration: none; border-bottom: 1px solid transparent; transition: border-color 0.2s ease; }
        .intro-text a:hover, .footer a:hover { border-bottom-color: #71c3bb; }
        .php-info tr { color: #fff; }
        code { background-color: #f4f4f4; padding: 2px 4px; border-radius: 4px; font-family: monospace; }
        </style>
</head>
<body>
    <div class="container">
        <header class="header{$headerClass}">
            <h1 class="title">PHP - NGINX</h1>
            <div class="intro-text">
                Hello there! This is just a generic entrypoint of the PHP - NGINX docker image. You can simply override it by mounting your own application in the <code>/var/www/html</code> folder or building your own image based on this one.
                The public files must be located in the <code>/var/www/html/public</code> folder.
                You are currently running the container in {$appEnv} mode.
            </div>
        </header>
        {$info}
        <footer class="footer">
            You can learn more about this image on <a href="https://github.com/Neunerlei/docker-images/blob/main/docs/php-nginx.md" target="_blank" rel="noopener noreferrer">GitHub</a>.
            Find me on <a href="https://neunerlei.eu" target="_blank" rel="noopener noreferrer">my website</a>
        </footer>
    </div>
</body>
</html>
HTML;

echo $content;
