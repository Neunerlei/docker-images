# Docker Images

A collection of Docker images; optimized for production use with common extensions and configurations.

> These images are in general for my private/professional projects. I try to keep them updated and secure and promise not to include any breaking changes without notice. However, I cannot guarantee the same level of support and stability as official images. Use at your own risk. All images are automatically build via GitHub Actions regularly to include the latest security patches from the base images.

## Available Images 

- **[nginx](docs/nginx.md)**: Minimal NGINX web server / reverse proxy
- **[node-nginx](docs/node-nginx.md)**: Node.js in a box with NGINX as reverse proxy
- **[php-nginx](docs/php-nginx.md)**: PHP with NGINX included (from PHP 8.5 onwards, and PHP 8.4 as legacy)
- **[php (deprecated)](docs/php.md)**: PHP-FPM only (without NGINX) (legacy, deprecated since PHP 8.4)
- **[python-nginx](docs/python-nginx.md)**: Python in a box with NGINX as reverse proxy

## Skill for AI Coding Agents

This repository ships a skill in [`skills/neunerlei-docker-images`](skills/neunerlei-docker-images) that teaches AI coding agents how these images work: the entrypoint modes, all environment variables and their defaults, the `/container/custom` mount, the filename-marker system, templating, and multi-stage build mode. With the skill installed, your agent can write docker-compose files, Dockerfiles and debug output for these images without guessing — and without you pasting documentation into the chat.

### Install With the `skills` CLI

The easiest way is the [`skills`](https://github.com/vercel-labs/skills) CLI, which knows the skill directory layout of the common agents (Claude Code, OpenCode, Codex, Cursor, ...):

```bash
# See what this repository provides
npx skills add Neunerlei/docker-images --list

# Install into the current project (shared with your team via git)
npx skills add Neunerlei/docker-images --skill neunerlei-docker-images

# Install globally, so it is available in all your projects
npx skills add Neunerlei/docker-images --skill neunerlei-docker-images -g

# Install only for a specific agent
npx skills add Neunerlei/docker-images --skill neunerlei-docker-images -a claude-code
```

Alternatively, point the CLI directly at the skill's directory:

```bash
npx skills add https://github.com/Neunerlei/docker-images/tree/main/skills/neunerlei-docker-images
```

Installed skills can be checked and updated with `npx skills check` and `npx skills update`.

### Manual Installation

If you do not want to use the CLI, copy or clone the [`skills/neunerlei-docker-images`](skills/neunerlei-docker-images) directory into your agent's skills folder — for Claude Code that is `~/.claude/skills/` (global) or `.claude/skills/` (project). The skill consists of a `SKILL.md` and its `references/` directory; both travel together.

## Automated Image Build Process

Our Docker images are built and updated automatically using a smart GitHub Actions pipeline. This process ensures our images stay up-to-date with the latest security patches from their official base images (like `php`, `nginx`, or `node`).

### How It Works

1.  **Discovery:** On a regular schedule, our pipeline queries the Docker Hub API to find the newest official tags for a base image (e.g., it finds that `php:8.4` has been released).
2.  **Matrix Generation:** Based on a configuration in the workflow file, it decides which versions to build. For example, it might be configured to always build the 3 latest minor versions.
3.  **Cascading Source Selection:** For each version to be built (e.g., `php:8.4`), the pipeline intelligently finds the right set of source files from our `src/` directory. It looks for a directory matching the version number. If it can't find `src/php-nginx/8.4`, it looks for the next closest one, like `src/php-nginx/8.3`, and uses that as a template. This allows us to support new versions automatically without duplicating files.
4.  **Build & Publish:** The pipeline uses the selected source files to build, test, and push the new image (e.g., `neunerlei/php-nginx:8.4`) to Docker Hub. It also generates security attestations for supply chain integrity.
5.  **Documentation:** Finally, the pipeline automatically updates the HTML tag list for the image, providing a clear, user-facing view of all available and maintained versions.

### How to Support a New Version

Because of the "cascading" logic, most new base image releases (e.g., NGINX `1.28` when we support `1.27`) will build correctly with no changes required.

If a new version introduces a **breaking change**, you simply need to:
1.  Copy the last working version's source directory (e.g., `cp -r src/nginx/1.27 src/nginx/1.29`).
2.  Make the necessary fixes inside the new `src/nginx/1.29` directory.
3.  Commit the change. The pipeline will automatically pick up and use this new directory for all future `1.29.x` builds.

## Local Build Process

For development and testing, you can also build the images locally using the `bin/build.sh` script to build images.
It utilizes the same logic as the automated build system (see: [.github/.release/local-build.js](.github/.release/local-build.js)), reading the pipeline configuration and finding the correct source directories. For local development, however, you need to provide the exact version and type to build.

```bash
./bin/build.sh php 8.4 fpm-debian
```

Parameters:
- `IMAGE_NAME`: e.g., `php`
- `VERSION`: e.g., `8.4`
- `TYPE`: e.g., `fpm-debian` (the type is optional)

To build and push:

```bash
./bin/build.sh php 8.5 fpm-debian 
```

## Contributing

If you want to contribute to this project or want to learn how the internals of the images are designed, please check the [contributing documentation](docs/contributing.md) file. Also, the [automated build system documentation](.github/BUILD.md) might be of interest to you, to understand how the images are build and published.

## License

There is no license for these images. The licenses for the base images and included software apply; obviously.
Use, modify and distribute at your own risk and leisure. I do not take any responsibility for any damage caused by using these images. However! If you have any questions or problems, feel free to open an issue or contact me directly.
