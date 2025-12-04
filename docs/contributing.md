# Contributing

First off, thank you for considering contributing. This document is intended for developers who want to understand the architecture of this entrypoint framework and how to extend it, for example, by creating a new base image type (like Python or Ruby).

Our goal is to maintain a system that is layered, declarative, and extensible.

> **Important: ** Before you start reading here, make sure you have read the [BUILD.md](../.github/BUILD.md) document to understand how the automated build system works. You need to understand how the images are built to understand how we inherit from library base images.

## Core Design Decisions

Before creating a new image, it's essential to understand the core principles that govern this framework.

The framework is built on a two-layer principle:

-   **The Common Layer (`src/_common/v1/`):** This directory is the heart of the framework. It contains the core engine, standard utilities, default configuration steps, and common templates. It is intended to be generic and reusable across all container images. **Changes to this layer should be made with extreme care**, as they affect every image that uses it.
-   **The Image-Specific Layer (e.g. `src/node-nginx/24/`):** This directory contains everything unique to a specific image variant. This includes image-specific variables, new marker conditions, and templates that override or augment the common ones.

This layering allows us to maintain a consistent base of functionality while providing a clean, isolated space for image-specific customizations.

> **The Common Layer is Sacred:** Only modify `_common` if a feature is genuinely reusable across *all* current and future images.

### 1. **Shared Common Layer Architecture**

All images share a common base layer located in the `_common/v1/` directory:

```
_common/v1/
├── installer.sh           # Single build-time installer
├── bin/entrypoint/        # Runtime orchestration system
├── templates/             # Base configuration templates
```

**Rationale**: Rather than duplicating common functionality across images, we extract shared components into a reusable layer. This reduces maintenance burden and ensures consistency across all images.

**Implementation**: Multi-stage Docker builds with `--build-context common=../../_common` allows efficient sharing without bloating individual image contexts.

### 2. **Metadata-Driven Configuration (Marker System)**

This is the most powerful concept in the framework. Instead of writing complex `if/else` logic in shell scripts, we declare the conditions for a file's use directly in its filename. This makes the system's behavior visible at a glance.

The rules are simple and strict:

-   **`.` (dot) is the AND operator:** It separates logical groups. For a file to be processed, **all** of its `.`-separated groups that contain a known marker must be satisfied.
    -   `service.prod.https.conf`: Requires the `prod` condition AND the `https` condition to be true.
-   **`-or-` is the OR operator:** It separates clauses *within* a single logical group. For a group to be satisfied, **at least one** of its `-or-` clauses must be satisfied.
    -   `service.dev-or-test.conf`: Requires the `dev` condition OR the `test` condition to be true.

The parser for this DSL lives entirely within `for-each-filtered-file-in-dir.sh` and should not need to be modified.

```bash
# Examples
service.nginx.conf                    # Always loaded
service.prod.nginx.conf              # Production only  
service.https-or-special.nginx.conf  # HTTPS OR special mode
service.prod.https.nginx.conf        # Production AND HTTPS
```

**Rationale**:
- **Self-documenting**: Filename immediately shows loading conditions
- **No configuration files**: Reduces complexity and avoids YAML/JSON parsing
- **Extensible**: New markers can be added without modifying core logic
- **Atomic**: Each file's conditions are self-contained

**Technical Implementation**:
- `.` separates AND conditions
- `-or-` separates OR conditions within a group
- Registry pattern allows images to define custom markers

### 3. **Registry Pattern for Extensibility**

The framework uses two global associative arrays declared in `entrypoint.sh` to manage features.

-   `file_marker_condition_registry`: This is the primary registry. It's a map where keys are marker names (e.g., `"prod"`) and values are the names of the shell functions that evaluate the condition (e.g., `"_file_marker_is_prod"`). To add a new marker, you simply define its condition function and add an entry to this map.
-   `feature_registry`: A simpler, space-separated string that enables or disables large chunks of logic in the `step.d` scripts (e.g., enabling the entire Nginx or Supervisor setup). This is for coarse-grained control.

```bash
# Core system defines registries
declare -gA file_marker_condition_registry
declare -g feature_registry

# Images extend by adding entries
file_marker_condition_registry["composer"]="_file_marker_has_composer"
feature_registry="${feature_registry} nginx supervisor"
```

**Rationale**: Instead of hardcoding logic, we use registries that can be extended by individual images. This allows the core system to remain generic while enabling image-specific behaviors.

### 4. **Environment Variable Management System**

Variables are managed in three layers:
1. **Build-time**: `common-env.sh` provides defaults during both build and runtime
2. **Runtime**: Entrypoint steps can override/extend variables
3. **Shell Integration**: Bash wrapper ensures variables are available in all shell contexts

**Rationale**: Docker's environment variable inheritance is inconsistent across different execution contexts (`docker exec`, interactive shells, etc.). Our system ensures consistent variable availability.

### 5. **Template Rendering Engine**

```bash
# Simple variable substitution
render_template "template.conf" "output.conf"

# Selective substitution
render_template_with "VAR1 VAR2" "template.conf" "output.conf"
```

**Rationale**: Rather than complex templating languages, we use simple `${VAR}` substitution. This is:
- **Lightweight**: No external dependencies
- **Shell-native**: Uses bash parameter expansion
- **Secure**: Safe against injection attacks
- **Debuggable**: `[[DEBUG_VARS]]` marker for troubleshooting

### 6. **Feature Toggle System**

```bash
# Images declare their features
feature_registry="${feature_registry} nginx supervisor"

# Entrypoint steps conditionally execute
if [[ "$feature_registry" == *"nginx"* ]]; then
  # Configure nginx
fi
```

**Rationale**: Not all images need all features. A Python image might not need nginx, while a Node.js image might not need PHP-FPM. Feature toggles prevent unnecessary configuration overhead.

### 7. **Staged Entrypoint Orchestration**

The main `entrypoint.sh` script is a simple, dumb orchestrator. Its only jobs are:
1.  Declare the global registries (`file_marker_condition_registry` and `feature_registry`).
2.  Source all utility scripts from `util.d/` to populate functions and registries.
3.  Execute all setup scripts from `step.d/` in alphabetical order.
4.  Finally, `exec` the command passed to the container.

The `step.d/` directory enforces a predictable bootstrap sequence. Scripts are executed in alphabetical order based on their numeric prefix (e.g., `010-...` runs before `020-...`). This allows for a clear, debuggable setup process where each file has a single responsibility.

```
entrypoint/step.d/
├── 010-common-vars.sh     # Base configuration
├── 020-nginx.sh           # Web server setup  
├── 040-supervisor.sh      # Process manager
├── 060-user-setup.sh      # Permission handling
└── 100-execute-command.sh # Final command execution
```

**Rationale**: Complex initialization broken into logical stages that execute in order. Each image can:
- Add new steps by creating numbered files
- Override existing steps by providing same-numbered files
- Insert steps between existing ones using intermediate numbers

## File Organization Patterns

### Image Structure Convention

We aim to keep the structure of each image consistent for ease of navigation and maintenance.

```
image-name/
├── bin/entrypoint/
│   ├── step.d/            # Image-specific entrypoint steps
│   └── util.d/            # Image-specific utility functions
├── templates/             # Image-specific configuration templates  
├── src/                   # Application source code
└── Dockerfile
```

Inside a container these directories will also be available.

- `bin` will be available at `$CONTAINER_BIN_DIR` which defaults to `/usr/bin/container/`
- `templates` will be available at `$CONTAINER_TEMPLATE_DIR` which defaults to `/etc/container/templates/`
- `src` will be available at `/var/www/html/` or `/var/www/html/public` depending on the image type.

Every directory we put files into can be retrieved using a environment variable. Look for variables ending with `*_DIR`,
e.g. `CONTAINER_CERTS_DIR`, `NGINX_DIR` or `SUPERVISOR_DIR`.

### Naming Conventions

**Entrypoint Steps**: `NNN-descriptive-name.sh` (e.g., `015-image-vars.sh`)
- Lower numbers = earlier execution
- Use increments of 5-10 to allow insertion of intermediate steps

**Marker Functions**: `_file_marker_is_*()` or `_file_marker_has_*()`
- Prefix with underscore to indicate internal function
- Use descriptive names that match marker purpose

**Template Files**: Follow the marker convention in filenames
- `service.root.nginx.conf` - always loaded
- `worker.mode-worker.conf` - only in worker mode

## Adding a New Base Image

### 1. **Create Image Structure**

```bash
mkdir -p new-image/bin/entrypoint/{step.d,util.d}
mkdir -p new-image/templates
```

### 2. **Define Image-Specific Variables**

```bash
# new-image/bin/entrypoint/step.d/015-image-vars.sh
export IMAGE_SPECIFIC_VAR="default_value"
feature_registry="${feature_registry} nginx supervisor"
```

### 3. **Add Custom Markers**

```bash
# new-image/bin/entrypoint/util.d/image-markers.sh
_file_marker_is_debug_mode() {
  [[ "${DEBUG_MODE}" == "true" ]]
}
file_marker_condition_registry["debug"]=_file_marker_is_debug_mode
```

### 4. **Create Templates**

Follow marker conventions in template filenames and use `${VAR}` substitution for dynamic content.

### 5. **Dockerfile Pattern**

```dockerfile
# Key elements for all images
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

# Install common dependencies
RUN --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh

# Load common files  
RUN --mount=type=bind,from=common,source=v1,target=/tmp/common \
    cp -r /tmp/common/templates/* "$CONTAINER_TEMPLATE_DIR/" && \
    cp -r /tmp/common/bin/* "$CONTAINER_BIN_DIR/"

# Load image-specific files
COPY templates/ "$CONTAINER_TEMPLATE_DIR/"
COPY --chmod=+x bin/ "$CONTAINER_BIN_DIR/"
```

## Extension Patterns

### Adding Custom Markers

The framework supports two types of markers, distinguished by their function signature:

**1. Scalar Markers (Exact Match)**

These are for simple, boolean-like conditions. They are registered with an exact string.

-   **Registry Key:** An exact string (e.g., `"https"`).
-   **Condition Function Signature:** Must take **no arguments**.
-   **Example:**
    -   Filename: `my-config.https.conf`
    -   Registry: `file_marker_condition_registry["https"]=_file_marker_is_https`
    -   Function: `_file_marker_is_https() { [[ ... ]]; }`
    -   The function `_file_marker_is_https` is called with zero arguments.

**2. Wildcard Markers (Pattern Match)**

These are for dynamic, pattern-based conditions. They are registered with a `*` wildcard. This is the preferred method for related groups of conditions, like environments or modes.

-   **Registry Key:** A pattern ending in `*` (e.g., `"env-*"`).
-   **Condition Function Signature:** Must accept **one argument**, which will be the part of the filename that the `*` matched.
-   **Example:**
    -   Filename: `my-config.env-staging.conf`
    -   Registry: `file_marker_condition_registry["env-*"]=_file_marker_is_env`
    -   Function: `_file_marker_is_env() { local env_suffix="$1"; [[ ... ]]; }`
    -   The parser matches `env-staging` against the `env-*` pattern.
    -   The function `_file_marker_is_env` is called with `"staging"` as its first argument.

1. **Create marker function**:
```bash
_file_marker_meets_condition() {
  # Your logic here
  [[ "${MY_VAR}" == "expected_value" ]]
}
```
OR a wildcard version:
```bash
_file_marker_is_mode() {
  local mode_suffix="$1" # Will receive 'web', 'worker', 'build', etc.
  [[ "${CONTAINER_MODE}" == "${mode_suffix}" ]]
}
# Register the single wildcard handler
file_marker_condition_registry["mode-*"]=_file_marker_is_mode
```

2. **Register the marker**:
```bash
file_marker_condition_registry["my-marker"]=_file_marker_meets_condition
```

3. **Use in filenames**:
```bash
config.my-marker.conf          # Only when condition met
config.prod.my-marker.conf     # Production AND condition met  
config.dev-or-my-marker.conf   # Development OR condition met
```

### Adding Custom Features

```bash
# In your image's step file
feature_registry="${feature_registry} my-feature"

# In entrypoint step
if [[ "$feature_registry" == *"my-feature"* ]]; then
  echo "Configuring my-feature..."
  # Your configuration logic
fi
```

## How to Create a New Base Image (e.g., Python)

Let's walk through creating a new `python-nginx/3.12` image.

### Step 1: Create the Directory Structure

Create a new directory `src/python-nginx/3.12`. It should contain the standard directories for image-specific logic:

```
src/python-nginx/3.12/
├── bin/
│   └── entrypoint/
│       ├── step.d/
│       │   └── 015-image-vars.sh       # Python-specific variables
│       └── util.d/
│           └── python-conditions.sh  # Python-specific markers
├── templates/
│   └── supervisor/
│       └── conf.d/
│           └── gunicorn.service.mode-web.conf # Python-specific templates
└── Dockerfile
```

### Step 2: Write the `Dockerfile`

The `Dockerfile` for a new image should be minimal. It leverages the common installer and copies the common and image-specific files.

```dockerfile
# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE=python:3.12-slim-bookworm

FROM ${SOURCE_IMAGE}

# ... LABELs ...

# Run the common installer script
# Pass arguments to the installer if needed (e.g., --no-nginx)
# Add Python-specific dependencies via the ENV var
ENV INSTALLER_EXTRA_DEPENDENCIES="python3-pip python3-venv"
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=bind,from=common,source=v1,target=/tmp/common \
    bash /tmp/common/installer.sh

WORKDIR /var/www/html

# Load common and image-specific files
RUN --mount=type=bind,from=common,source=v1,target=/tmp/common \
    cp -r /tmp/common/bin/* "$CONTAINER_BIN_DIR/"
COPY --chmod=+x bin/ "$CONTAINER_BIN_DIR/"
COPY templates/ "$CONTAINER_TEMPLATE_DIR/"
RUN find "$CONTAINER_BIN_DIR" -type f -name "*.sh" -exec chmod +x {} \;

ENTRYPOINT ["/usr/bin/container/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
```
**Build Command:** Remember to build from the `src` directory with the common context:
`docker build --build-context common=../../_common -f python-nginx/3.12/Dockerfile -t my-python-image .`

### Step 3: Define Image-Specific Logic

-   **`bin/entrypoint/step.d/015-image-vars.sh`**: This is where you define and export environment variables specific to Python (e.g., `GUNICORN_WORKERS`, `PYTHONPATH`). This is also where you should set the `CONTAINER_MODE` and populate the `feature_registry` based on the image's purpose.
-   **`bin/entrypoint/util.d/python-conditions.sh`**: If your Python image needs a unique marker (e.g., `.mode-gunicorn`), define the condition function and register it here.

    ```bash
    # In python-conditions.sh
    _file_marker_is_gunicorn_mode() {
      [[ "${CONTAINER_MODE}" == "gunicorn" ]]
    }
    file_marker_condition_registry["mode-gunicorn"]=_file_marker_is_gunicorn_mode
    ```

### Step 4: Add Image-Specific Templates

Place any Supervisor or Nginx templates that are unique to the Python environment in the `templates/` directory. Use the file marker DSL to control when they are rendered (e.g., `gunicorn.service.mode-gunicorn.conf`).

## Build Optimization Strategies

### Layer Caching

The installer step is expensive, so structure Dockerfiles to maximize cache hits:

```dockerfile
# Stable layers first
RUN mount-installer-and-run

# Variable content later  
COPY src/ /app/
```

### Build Context Management

Use `--build-context` to share common files without bloating individual contexts:

```bash
docker build --build-context common=../../_common -t my-image .
```

## Testing and Debugging

### Debugging Templates

Add `[[DEBUG_VARS]]` to any template to see available variables:

```bash
# In template file
server_name ${NGINX_SERVER_NAME};
[[DEBUG_VARS]]  # Will exit with variable dump
```

## Advanced Topics & Gotchas

-   **The Bash Wrapper (`installer.sh`):** A wrapper script in `/bin/bash` is installed to automatically `source /etc/container-vars.sh`. This ensures that variables exported by `step.d/050-export-vars.sh` are available in `docker exec` sessions. Do not remove this "black magic."
-   **Docker Build Cache:** The `Dockerfile` uses a single `RUN --mount` to copy the `_common` files. This means any change in `_common` will invalidate this layer. This is an intentional trade-off for simplicity. The `installer.sh` step is separate and will remain cached unless it changes.

### File Discovery

The marker system uses filesystem operations to discover files. For directories with many files, consider organizing into subdirectories to improve performance.

### Variable Expansion

The `get_all_vars()` function filters out bash internals and common system variables to reduce template processing overhead.
It also filters out variables starting with a lower case letter or an underscore, as these are typically not intended for template use.

## Future Extensibility

The architecture is designed to accommodate future needs:

- **Version Management**: `_common/v1/` allows for `v2/` with breaking changes
- **Plugin System**: Registry pattern supports unlimited extensions
- **Multi-Architecture**: Build system works with different CPU architectures
- **Config Validation**: Framework could be extended with validation hooks

This design enables building sophisticated, maintainable container images that share common functionality while remaining flexible and extensible.
