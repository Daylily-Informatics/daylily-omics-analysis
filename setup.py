from setuptools import setup, find_packages

DAYOA_CLI_SCRIPTS = [
    "bin/day_activate",
    "bin/day_deactivate",
    "bin/day_help",
    "bin/day_monitor",
    "bin/day_run",
    "bin/day_set_genome_build",
    "bin/day-activate",
    "bin/day-deactivate",
    "bin/day-help",
    "bin/day-monitor",
    "bin/day-run",
    "bin/day-set-genome-build",
    "bin/dy-a",
    "bin/dy-d",
    "bin/dy-g",
    "bin/dy-h",
    "bin/dy-m",
    "bin/dy-r",
]

setup(
    name="daylily-omics-analysis",
    packages=find_packages(),
    scripts=DAYOA_CLI_SCRIPTS,
    install_requires=[
        # Add dependencies here
    ],
    package_data={
        "": ["scripts/*.sh"],  # Include all `.sh` files under the `scripts/` directory
        "daylily_omics_analysis": ["data/*.json"],
    },
)
