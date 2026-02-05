# Processes a named template registration from the in-memory manifest.
# This function is the core of the dynamic configuration system. It is
# idempotent and will only process a given template name once.
#
# Usage:
#   process_tpl "template-name" ["optional_callback_function"]
#
# Callback Function Signature (for 'callback' type templates):
# 1. Callbacks for single files:
#    callback_function "output_path" "template_name" ["source_path"]
#    -> source_path only if a source was defined, and the callback is used as an additional filter
# 2. Callbacks for directories:
#    callback_function "output_path" "template_name" ["source_path"] "pattern"
#    -> source_path and pattern only if defined, allowing the callback to further filter files
#       if no source path is defined, source_path will be an empty string
#
function process_tpl() {
    local name="$1"
    local callback="$2"

    if [[ -n "${processed_tpl_names[$name]}" ]]; then
        echo "[TEMPLATE] Warning: Template '$name' has already been processed. Skipping." >&2
        return 0
    fi

    local line="${template_manifest[$name]}"
    if [[ -z "$line" ]]; then
        echo "[TEMPLATE] Error: No registration for '$name'." >&2
        exit 1
    fi

    echo "[TEMPLATE] Processing template group: $name"

    # We now get a |-separated string of sources
    IFS=$'\t' read -r type _ sources_str extra <<<"$line"

    local work_path="${CONTAINER_WORK_DIR}/${name}"

    case $type in
    file | dir)
        # --- THIS IS THE KEY CHANGE: Deserialize sources into an array ---
        local -a source_paths=()
        IFS='|' read -r -a source_paths <<<"$sources_str"

        if [[ -n "$callback" ]]; then
            # Provide the callback with the full context: all sources at once.
            # This allows for powerful override logic.
            "$callback" "$work_path" "$name" "${source_paths[@]}" "$extra"
        else
            # Default behavior: render from all sources into the single work directory.
            echo "[TEMPLATE] Rendering sources for '$name': ${source_paths[*]}"
            for source_path in "${source_paths[@]}"; do
                if [[ "$type" == "file" ]]; then
                    render_template "$source_path" "${work_path}"
                else
                    render_filtered_templates_in_dir "$source_path" "$work_path" "$extra"
                fi
            done
        fi
        ;;

    cb_file | cb_dir)
        if [[ -z "$callback" ]]; then
            echo "[TEMPLATE] Fatal: Callback template '$name' requires a callback function." >&2
            exit 1
        fi
        # For callbacks, the source array is empty, but we still pass the placeholder
        # and pattern for a consistent function signature.
        "$callback" "$work_path" "$name" "" "$extra"
        ;;
    *)
        echo "[TEMPLATE] Fatal: Unknown template type '$type' for name '$name'." >&2
        exit 1
        ;;
    esac

    processed_tpl_names[$name]=1
}

# Allows a previously processed template to be re-processed.
# This is useful in scenarios where the template's output
# may depend on dynamic state that can change during execution.
# Usage:
#   allow_reprocessing_tpl "template-name"
function allow_reprocessing_tpl() {
    local name="$1"
    unset processed_tpl_names[$name]
}
