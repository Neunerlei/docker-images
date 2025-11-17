<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Docker Image Tags - ${IMAGE_NAME}</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #ffffff;
            padding: 20px;
            min-height: 100vh;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 20px;
        }

        .header {
            text-align: center;
            margin-bottom: 3rem;
            padding-bottom: 2rem;
            border-bottom: 1px solid #e0e0e0;
        }

        .footer {
            text-align: center;
            margin-top: 3rem;
            padding-top: 2rem;
            border-top: 1px solid #e0e0e0;
            font-size: 0.9rem;
            color: #999;
        }

        .title {
            font-size: 2.5rem;
            font-weight: 600;
            color: #2c3e50;
            margin-bottom: 1rem;
        }

        .intro-text {
            font-size: 1.1rem;
            color: #666;
            max-width: 800px;
            margin: 0 auto;
            line-height: 1.7;
        }

        .intro-text a,
        .footer a {
            color: #71c3bb;
            text-decoration: none;
            border-bottom: 1px solid transparent;
            transition: border-color 0.2s ease;
        }

        .intro-text a:hover,
        .footer a:hover {
            border-bottom-color: #71c3bb;
        }

        .deprecated-warning {
            background: linear-gradient(135deg, #fee2e2 0%, #fecaca 100%);
            border: 1px solid #f87171;
            border-radius: 12px;
            padding: 1.5rem;
            margin: 2rem auto;
            max-width: 800px;
            box-shadow: 0 4px 12px rgba(248, 113, 113, 0.1);
        }

        .deprecated-warning.show {
            display: block;
            animation: slideIn 0.4s ease-out;
        }

        .deprecated-warning-icon {
            display: inline-block;
            font-size: 1.5rem;
            margin-right: 0.75rem;
            vertical-align: middle;
        }

        .deprecated-warning-title {
            font-size: 1.3rem;
            font-weight: 600;
            color: #dc2626;
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
        }

        .deprecated-warning-text {
            color: #991b1b;
            font-size: 1rem;
            line-height: 1.6;
        }

        .tags-section {
            margin-bottom: 3rem;
        }

        .section-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }

        .section-title::before {
            content: '';
            width: 4px;
            height: 1.5rem;
            border-radius: 2px;
        }

        .section-title.active::before {
            background-color: #9fcc8c;
        }

        .section-title.available::before {
            background-color: #d6ba6a;
        }

        .section-title.deprecated::before {
            background-color: #ef4444;
        }

        .tags-grid {
            display: flex;
            flex-wrap: wrap;
            gap: 0.75rem;
        }

        .tag-pill {
            display: inline-flex;
            align-items: center;
            padding: 0.5rem 1rem;
            border-radius: 20px;
            text-decoration: none;
            font-weight: 500;
            font-size: 0.9rem;
            transition: all 0.2s ease;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            border: 1px solid transparent;
        }

        .tags-grid.active .tag-pill {
            background-color: #9fcc8c;
            color: #2c5530;
        }

        .tags-grid.active .tag-pill:hover {
            background-color: #8bb97a;
            box-shadow: 0 4px 8px rgba(159, 204, 140, 0.3);
            transform: translateY(-1px);
        }

        .tags-grid.available .tag-pill {
            background-color: #d6ba6a;
            color: #5c4a2b;
        }

        .tags-grid.available .tag-pill:hover {
            background-color: #c9ab5a;
            box-shadow: 0 4px 8px rgba(214, 186, 106, 0.3);
            transform: translateY(-1px);
        }

        .tags-grid.deprecated .tag-pill {
            background-color: #ef4444;
            color: #ffffff;
            border: 1px solid #dc2626;
        }

        .tags-grid.deprecated .tag-pill:hover {
            background-color: #dc2626;
            box-shadow: 0 4px 8px rgba(239, 68, 68, 0.4);
            transform: translateY(-1px);
        }

        /* Responsive Design */
        @media (max-width: 768px) {
            body {
                padding: 15px;
            }

            .container {
                padding: 0 10px;
            }

            .title {
                font-size: 2rem;
            }

            .intro-text {
                font-size: 1rem;
            }

            .deprecated-warning {
                padding: 1.25rem;
                margin: 1.5rem auto;
            }

            .deprecated-warning-title {
                font-size: 1.2rem;
            }

            .deprecated-warning-text {
                font-size: 0.95rem;
            }

            .section-title {
                font-size: 1.3rem;
            }

            .tag-pill {
                font-size: 0.85rem;
                padding: 0.45rem 0.9rem;
            }
        }

        @media (max-width: 480px) {
            .title {
                font-size: 1.7rem;
            }

            .deprecated-warning {
                padding: 1rem;
                margin: 1rem auto;
            }

            .deprecated-warning-icon {
                font-size: 1.3rem;
                margin-right: 0.5rem;
            }

            .deprecated-warning-title {
                font-size: 1.1rem;
            }

            .deprecated-warning-text {
                font-size: 0.9rem;
            }

            .tag-pill {
                font-size: 0.8rem;
                padding: 0.4rem 0.8rem;
            }

            .tags-grid {
                gap: 0.5rem;
            }
        }
    </style>
</head>
<body>
<div class="container">
    <header class="header">
        <h1 class="title">Tags of image ${IMAGE_NAME}</h1>
        <div class="intro-text">
            This image is available at <a href="https://hub.docker.com/r/${IMAGE}" target="_blank" rel="noopener noreferrer">Docker Hub</a>.
            We maintain two types of tags: <strong>actively maintained</strong> images are built twice a week from their sources to keep track with upstream patches, while <strong>available</strong> images are older versions that are no longer built regularly and should be phased out as soon as possible.
        </div>
        ${DEPRECATED_WARNING}
    </header>

    <main>
        ${DEPRECATED_SECTION}
        ${MAINTAINED_SECTION}
        ${AVAILABLE_SECTION}
    </main>

    <footer class="footer">
        You can learn more about this image on <a href="https://github.com/Neunerlei/docker-images" target="_blank" rel="noopener noreferrer">GitHub</a>.
        Find me on <a href="https://neunerlei.eu" target="_blank" rel="noopener noreferrer">my website</a>
    </footer>
</div>
</body>
</html>
