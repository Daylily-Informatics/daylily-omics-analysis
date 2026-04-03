from setuptools import setup, find_packages

setup(
    name="daylily-omics-analysis",
    version="0.7.357",
    packages=find_packages(),
    install_requires=[
        # Add dependencies here
    ],
    package_data={
        "": ["scripts/*.sh"],  # Include all `.sh` files under the `scripts/` directory
    },
)
