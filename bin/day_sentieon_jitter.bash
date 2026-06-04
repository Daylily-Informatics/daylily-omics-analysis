#!/usr/bin/env bash

dayoa_sentieon_start_jitter() {
    local max_seconds="${DAYOA_SENTIEON_START_JITTER_MAX_SECONDS:-0}"
    if [[ "$max_seconds" == "0" || -z "$max_seconds" ]]; then
        return 0
    fi
    if [[ ! "$max_seconds" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: DAYOA_SENTIEON_START_JITTER_MAX_SECONDS must be a positive integer or 0; got '$max_seconds'." >&2
        return 64
    fi
    local delay=$(( (RANDOM % max_seconds) + 1 ))
    echo "DAYOA Sentieon start jitter: sleeping ${delay}s before $*" >&2
    sleep "$delay"
}

dayoa_require_executable() {
    local executable="$1"
    if [[ -z "$executable" ]]; then
        echo "ERROR: Sentieon executable path/name is empty." >&2
        return 64
    fi
    if [[ "$executable" == */* ]]; then
        if [[ ! -x "$executable" ]]; then
            echo "ERROR: Sentieon executable not found or not executable: $executable" >&2
            return 127
        fi
        return 0
    fi
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "ERROR: Sentieon executable not found on PATH: $executable" >&2
        return 127
    fi
}
