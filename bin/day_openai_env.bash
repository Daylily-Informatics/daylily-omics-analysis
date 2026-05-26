#!/usr/bin/env bash

# Source this file before day-run, or let profile_env.bash source it when
# DAYOA_OPENAI_TOKEN_FILE_ENABLE=1. It copies a token file to the ubuntu
# account token path when needed, then exports the variables that MultiQC and
# Apptainer/Singularity need.

_dayoa_openai_return() {
    return "$1" 2>/dev/null || exit "$1"
}

_dayoa_openai_source="${DAYOA_OPENAI_TOKEN_SOURCE:-${HOME}/.config/openai/tok.tok}"
_dayoa_openai_target="${DAYOA_OPENAI_TOKEN_TARGET:-/home/ubuntu/.config/openai/tok.tok}"
_dayoa_openai_model="${DAYOA_OPENAI_MODEL:-gpt-5.5}"

if [[ -z "${_dayoa_openai_source}" ]]; then
    echo "ERROR: DAYOA_OPENAI_TOKEN_SOURCE resolved to an empty path." >&2
    _dayoa_openai_return 2
fi

if [[ -z "${_dayoa_openai_target}" ]]; then
    echo "ERROR: DAYOA_OPENAI_TOKEN_TARGET resolved to an empty path." >&2
    _dayoa_openai_return 2
fi

if [[ ! -f "${_dayoa_openai_source}" ]]; then
    echo "ERROR: OpenAI token file not found: ${_dayoa_openai_source}" >&2
    _dayoa_openai_return 2
fi

if [[ ! -s "${_dayoa_openai_source}" ]]; then
    echo "ERROR: OpenAI token file is empty: ${_dayoa_openai_source}" >&2
    _dayoa_openai_return 2
fi

_dayoa_openai_target_dir="$(dirname "${_dayoa_openai_target}")"
if [[ "${_dayoa_openai_source}" != "${_dayoa_openai_target}" ]]; then
    install -d -m 700 "${_dayoa_openai_target_dir}" || _dayoa_openai_return 2
    install -m 600 "${_dayoa_openai_source}" "${_dayoa_openai_target}" || _dayoa_openai_return 2
    if [[ "$(id -u)" == "0" ]] && id ubuntu >/dev/null 2>&1; then
        chown ubuntu:ubuntu "${_dayoa_openai_target_dir}" "${_dayoa_openai_target}" || _dayoa_openai_return 2
    fi
else
    chmod 700 "${_dayoa_openai_target_dir}" || _dayoa_openai_return 2
    chmod 600 "${_dayoa_openai_target}" || _dayoa_openai_return 2
fi

if [[ ! -f "${_dayoa_openai_target}" ]]; then
    echo "ERROR: OpenAI token target file was not created: ${_dayoa_openai_target}" >&2
    _dayoa_openai_return 2
fi

_dayoa_openai_token="$(LC_ALL=C tr -d '\r\n' < "${_dayoa_openai_target}")"
if [[ -z "${_dayoa_openai_token}" ]]; then
    echo "ERROR: OpenAI token target file is empty after newline trimming: ${_dayoa_openai_target}" >&2
    _dayoa_openai_return 2
fi

if [[ "${_dayoa_openai_token}" == *[[:space:]]* ]]; then
    echo "ERROR: OpenAI token contains whitespace after newline trimming: ${_dayoa_openai_target}" >&2
    _dayoa_openai_return 2
fi

export OPENAI_API_KEY="${_dayoa_openai_token}"
export MULTIQC_AI_SUMMARY=1
export MULTIQC_AI_PROVIDER=openai
export MULTIQC_AI_MODEL="${_dayoa_openai_model}"

export APPTAINERENV_OPENAI_API_KEY="${OPENAI_API_KEY}"
export APPTAINERENV_MULTIQC_AI_SUMMARY="${MULTIQC_AI_SUMMARY}"
export APPTAINERENV_MULTIQC_AI_PROVIDER="${MULTIQC_AI_PROVIDER}"
export APPTAINERENV_MULTIQC_AI_MODEL="${MULTIQC_AI_MODEL}"

export SINGULARITYENV_OPENAI_API_KEY="${OPENAI_API_KEY}"
export SINGULARITYENV_MULTIQC_AI_SUMMARY="${MULTIQC_AI_SUMMARY}"
export SINGULARITYENV_MULTIQC_AI_PROVIDER="${MULTIQC_AI_PROVIDER}"
export SINGULARITYENV_MULTIQC_AI_MODEL="${MULTIQC_AI_MODEL}"

unset _dayoa_openai_token
unset _dayoa_openai_source
unset _dayoa_openai_target
unset _dayoa_openai_target_dir
unset _dayoa_openai_model
unset -f _dayoa_openai_return

return 0 2>/dev/null || exit 0
