. /opt/slurm/etc/slurm.sh

dayoa_user="$(id -un)"
dayoa_host="${HOSTNAME:-$(hostname)}"

export APPTAINER_TMPDIR="/fsx/scratch/dayoa_apptainer_tmp/${dayoa_user}"
export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"
export APPTAINER_CACHEDIR="/fsx/resources/environments/apptainer_cache/${dayoa_user}/${dayoa_host}"
export SINGULARITY_CACHEDIR="${APPTAINER_CACHEDIR}"

mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}" || return 1

return 0
