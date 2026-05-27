dayoa_user="$(id -un)"
dayoa_host="${HOSTNAME:-$(hostname)}"

if [[ "${DAY_BIOME:-}" == "MAC" ]]; then
    if [[ -z "${DAYOA_MAC_STATE_DIR:-}" ]]; then
        echo "ERROR: DAYOA_MAC_STATE_DIR is not set for macOS local mode." >&2
        return 1
    fi
    export APPTAINER_TMPDIR="${DAYOA_MAC_STATE_DIR}/apptainer_tmp/${dayoa_user}"
    export APPTAINER_CACHEDIR="${DAYOA_MAC_STATE_DIR}/apptainer_cache/${dayoa_user}/${dayoa_host}"
else
    export APPTAINER_TMPDIR="/fsx/scratch/dayoa_apptainer_tmp/${dayoa_user}"
    export APPTAINER_CACHEDIR="/fsx/tmp/apptainer_cache/${dayoa_user}/${dayoa_host}"
fi
export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"
export SINGULARITY_CACHEDIR="${APPTAINER_CACHEDIR}"

mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}" || return 1

if [[ "${DAYOA_OPENAI_TOKEN_FILE_ENABLE:-}" == "1" ]]; then
    if [[ -z "${DAY_ROOT:-}" ]]; then
        echo "ERROR: DAY_ROOT is not set; cannot source bin/day_openai_env.bash." >&2
        return 1
    fi
    source "${DAY_ROOT}/bin/day_openai_env.bash" || return 1
fi

return 0
