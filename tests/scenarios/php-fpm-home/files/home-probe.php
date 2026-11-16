<?php
// HOME probe for the php-fpm worker environment (plan §2.2 note — /proc
// environ is unreliable for FPM workers, so the runtime itself reports).
// Reported as response headers (the suite records X-Nl-Test-* headers),
// values are paths/ids — deterministic per build.
$home = getenv('HOME');
header('X-Nl-Test-Home: ' . ($home === false ? '(unset)' : $home));
if (function_exists('posix_getpwuid')) {
    $pw = posix_getpwuid(posix_geteuid());
    header('X-Nl-Test-Euid: ' . ($pw['name'] ?? '(unknown)') . ':' . ($pw['dir'] ?? '(unknown)'));
} else {
    header('X-Nl-Test-Euid: (posix unavailable)');
}
echo 'fpm-home-probe-ok';
