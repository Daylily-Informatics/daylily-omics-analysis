. /opt/slurm/etc/slurm.sh

dayoa_user="$(id -un)"
dayoa_host="${HOSTNAME:-$(hostname)}"

export APPTAINER_TMPDIR="/fsx/scratch/dayoa_apptainer_tmp/${dayoa_user}"
export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"
export APPTAINER_CACHEDIR="/fsx/tmp/apptainer_cache/${dayoa_user}/${dayoa_host}"
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
