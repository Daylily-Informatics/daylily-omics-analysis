from daylily_ec.aws.ssm import run_shell


SCRIPT = r"""set -euo pipefail
id -un
printf 'SHELL_ENV=%s\n' "${SHELL:-}"
printf 'SHELL_PROC=%s\n' "$(ps -p $$ -o comm=)"
command -v day-clone
command -v tmux
command -v squeue

for p in \
  /fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R1.fastq.gz \
  /fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R2.fastq.gz \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.2.bundle \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle \
  /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20-20260528.vcf.gz \
  /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz
do
  if [[ -f "$p" ]]; then
    printf 'FILE\t%s\t%s\n' "$(stat -c %s "$p")" "$p"
  elif [[ -d "$p" ]]; then
    printf 'DIR\t-\t%s\n' "$p"
  else
    printf 'MISSING\t-\t%s\n' "$p"
  fi
done

echo TRUTH_DIRS
find /fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003 \
  -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
"""


def main() -> None:
    result = run_shell(
        "i-05815cdeec4a6dad8",
        "us-west-2",
        SCRIPT,
        profile="lsmc",
        timeout=180,
        comment="HG003 pangenome 10.0.4 asset check",
    )
    print(result.stdout, end="")
    print(result.stderr, end="")


if __name__ == "__main__":
    main()
