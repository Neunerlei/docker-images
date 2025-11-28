// Small node.js script to handle a web request on port 80 and respond with "Hello, World!"
const http = require('http');

const hostname = '0.0.0.0';
const port = 3000;

// Render the environment variables in an HTML template
let envVars = '';
let headerClass = '';
if(process.env.NODE_ENV !== 'production') {
    headerClass = ' development-mode';
    envVars = `
<div class="environment-variables">
    <h2>Environment Variables</h2>
    <ul>${Object.keys(process.env).sort().map(key => `<li><strong>${key}:</strong> ${process.env[key]}</li>`).join('')}</ul>
</div>`;
}

const content = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="ROBOTS" content="NOINDEX,NOFOLLOW,NOARCHIVE">
    <title>Node.js - NGINX</title>
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
        .environment-variables { margin-top: 2rem; text-align: left; max-width: 800px; margin-left: auto; margin-right: auto; }
        .environment-variables h2 { font-size: 1.5rem; margin-bottom: 1rem; color: #2c3e50; }
        .environment-variables ul { list-style-type: none; }
        .environment-variables li { background-color: #f9f9f9; margin-bottom: 0.5rem; padding: 0.5rem 1rem; border-radius: 4px; font-family: monospace; }
        code { background-color: #f4f4f4; padding: 2px 4px; border-radius: 4px; font-family: monospace; }
        </style>    
</head>
<body>
    <div class="container">
        <header class="header${headerClass}">
            <h1 class="title">Node.js - NGINX</h1>
            <div class="intro-text">
                Hello there! This is just a generic entrypoint of the Node.js - NGINX docker image. You can simply override it by mounting your own application in the <code>/var/www/html</code> folder or building your own image based on this one.
                Static images will be served by NGINX if they are placed in the <code>/var/www/html/public</code> folder.
                You are currently running the container in ${process.env.NODE_ENV || 'production'} mode.
            </div>
        </header>
        ${envVars}
        <footer class="footer">
            You can learn more about this image on <a href="https://github.com/Neunerlei/docker-images/blob/main/docs/node-nginx.md" target="_blank" rel="noopener noreferrer">GitHub</a>.
            Find me on <a href="https://neunerlei.eu" target="_blank" rel="noopener noreferrer">my website</a>
        </footer>
    </div>
</body>
</html>
`;

const server = http.createServer((req, res) => {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html');
    res.end(content);
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});
