from setuptools import setup, find_packages

setup(
    name="daylily-omics-analysis",
    packages=find_packages(),
    install_requires=[
        # Add dependencies here
    ],
    package_data={
        "": ["scripts/*.sh"],  # Include all `.sh` files under the `scripts/` directory
        "daylily_omics_analysis": ["data/*.json"],
    },
)
