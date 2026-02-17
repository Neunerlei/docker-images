import os
from flask import Flask, request, render_template_string

# The WSGI callable that Gunicorn will use.
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Default error pages
# ---------------------------------------------------------------------------
ERROR_PAGES_DIR = '/var/www/errors'

def _read_error_page(status_code):
    """Return the contents and content-type for a given status code,
    respecting the Accept header for JSON vs HTML."""
    if 'application/json' in request.headers.get('Accept', ''):
        ext, content_type = 'json', 'application/json'
    else:
        ext, content_type = 'html', 'text/html; charset=utf-8'

    # Try the exact match first, then fall back
    candidates = [
        os.path.join(ERROR_PAGES_DIR, f'{status_code}.{ext}'),
        os.path.join(ERROR_PAGES_DIR, f'{status_code}.html'),
        os.path.join(ERROR_PAGES_DIR, '500.html'),
    ]

    for filepath in candidates:
        try:
            with open(filepath, 'r') as f:
                return f.read(), status_code, {'Content-Type': content_type}
        except FileNotFoundError:
            continue

    # Last resort — no error page files found at all
    return 'Internal Server Error', 500

for code in (400, 401, 403, 404, 500):
    app.register_error_handler(code, lambda e, c=code: _read_error_page(c))

@app.route('/')
def hello_world():
    # Detect the environment, defaulting to 'production'.
    app_env = os.getenv('APP_ENV', 'production')
    
    env_vars_html = ''
    header_class = ''
    
    # If not in production, generate the HTML for the environment variables table.
    if app_env != 'prod':
        header_class = ' development-mode'
        # Get all environment variables from os.environ as a dictionary.
        # Sort them by key for a consistent, readable order.
        sorted_vars = sorted(os.environ.items())
        
        # Build the list items for the HTML.
        list_items = "".join(f"<li><strong>{key}:</strong> {value}</li>" for key, value in sorted_vars)
        
        env_vars_html = f"""
        <div class="environment-variables">
            <h2>Environment Variables</h2>
            <ul>{list_items}</ul>
        </div>
        """

    # Use an f-string for easy templating of the main HTML content.
    template = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="ROBOTS" content="NOINDEX,NOFOLLOW,NOARCHIVE">
        <title>Python - Nginx</title>
        <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; background-color: #ffffff; padding: 20px; min-height: 100vh; }}
        .container {{ max-width: 1200px; margin: 0 auto; padding: 0 20px; }}
        .header {{ text-align: center; }}
        .header.development-mode {{ margin-bottom: 3rem; padding-bottom: 2rem; border-bottom: 1px solid #e0e0e0; }}
        .footer {{ text-align: center; margin-top: 3rem; padding-top: 2rem; border-top: 1px solid #e0e0e0; font-size: 0.9rem; color: #999; }}
        .title {{ font-size: 2.5rem; font-weight: 600; color: #2c3e50; margin-bottom: 1rem; }}
        .intro-text {{ font-size: 1.1rem; color: #666; max-width: 800px; margin: 0 auto; line-height: 1.7; }}
        .intro-text a, .footer a {{ color: #71c3bb; text-decoration: none; border-bottom: 1px solid transparent; transition: border-color 0.2s ease; }}
        .intro-text a:hover, .footer a:hover {{ border-bottom-color: #71c3bb; }}
        .environment-variables {{ margin-top: 2rem; text-align: left; max-width: 800px; margin-left: auto; margin-right: auto; }}
        .environment-variables h2 {{ font-size: 1.5rem; margin-bottom: 1rem; color: #2c3e50; }}
        .environment-variables ul {{ list-style-type: none; }}
        .environment-variables li {{ background-color: #f9f9f9; margin-bottom: 0.5rem; padding: 0.5rem 1rem; border-radius: 4px; font-family: monospace; word-wrap: break-word; }}
        code {{ background-color: #f4f4f4; padding: 2px 4px; border-radius: 4px; font-family: monospace; }}
        </style>
    </head>
    <body>
        <div class="container">
            <header class="header{header_class}">
                <h1 class="title">Python - Nginx</h1>
                <div class="intro-text">
                    Hello there! This is a generic entrypoint for the Python - Nginx docker image. You can simply override it by mounting your own application in the <code>/var/www/html</code> folder or building your own image based on this one.
                    <strong>Important:</strong> If your app module does not live in <code>/var/www/html/server.py:app</code>, you will need to set the <code>PYTHON_APP_MODULE</code> environment variable to point to the correct location.
                    Statically served files can be located in the <code>/var/www/html/static</code> folder.
                    You are currently running in <code>{app_env}</code> mode.
                </div>
            </header>
            
            {env_vars_html}

            <footer class="footer">
                You can learn more about this image on <a href="https://github.com/Neunerlei/docker-images/blob/main/docs/python-nginx.md" target="_blank" rel="noopener noreferrer">GitHub</a>.
                Find me on <a href="https://neunerlei.eu" target="_blank" rel="noopener noreferrer">my website</a>
            </footer>
        </div>
    </body>
    </html>
    """
    return render_template_string(template)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
