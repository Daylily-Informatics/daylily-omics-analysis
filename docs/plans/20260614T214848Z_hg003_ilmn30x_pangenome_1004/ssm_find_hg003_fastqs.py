from daylily_ec.aws.ssm import run_shell


SCRIPT = r"""set -euo pipefail
echo SEARCH_HG003_30X_FASTQS
find /fsx \
  \( -path /fsx/scratch -o -path /fsx/analysis_results -o -path /fsx/run_dir_mounts \) -prune -o \
  -type f \( -name 'HG003_30x_R1.fastq.gz' -o -name 'HG003_30x_R2.fastq.gz' -o -name '*HG003*30x*R1*.fastq.gz' -o -name '*HG003*30x*R2*.fastq.gz' \) \
  -printf '%s\t%p\n' | sort
echo SEARCH_HG003_GIAB_NOVASEQ_DIRS
find /fsx \
  \( -path /fsx/scratch -o -path /fsx/analysis_results -o -path /fsx/run_dir_mounts \) -prune -o \
  -type d \( -name 'NovaSeqX_WHGS_TruSeqPF_HG002-007' -o -name '*HG003*30x*' \) \
  -printf '%p\n' | sort | head -200
"""


def main() -> None:
    result = run_shell(
        "i-05815cdeec4a6dad8",
        "us-west-2",
        SCRIPT,
        profile="lsmc",
        timeout=300,
        comment="Find HG003 30x FASTQs for pangenome 10.0.4",
    )
    print(result.stdout, end="")
    print(result.stderr, end="")


if __name__ == "__main__":
    main()
