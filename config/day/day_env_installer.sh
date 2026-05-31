#!/usr/bin/env bash

################################################################################
# Script Name: day_env_installer.sh
# Description: Sets up Miniconda and installs the DAYOA conda environment.
# Usage:       source ./day_env_installer.sh DAYOA
#              Provide 'DAYOA' as the argument to start the installation.
#              If the 'DAYOA' environment already exists, the script will prompt accordingly.
################################################################################


# Function to display usage information
usage() {
    echo "Usage: source $0 DAYOA"
    echo "This script installs Miniconda and sets up the DAYOA conda environment."
    echo "Provide 'DAYOA' as the argument to start the installation."
    return 2
}

# Check if the correct argument is provided
DY_ENVNAME="DAYOA"
DAYOA_MERMAID_CLI_PACKAGE="@mermaid-js/mermaid-cli@11.15.0"
if [[ "$1" != "$DY_ENVNAME" ]]; then
    echo "Hello! This is the __ $DY_ENVNAME __ installation script."
    echo ""
    echo "The DAYOA environment installs the software needed to trigger Snakemake and run the Day (dy-) CLI."
    echo "To run and start the install, provide 'DAYOA' as the argument."
    echo ""
    echo "Usage: $0 DAYOA"
    echo ""
    echo "If you have an existing DAYOA install, you may need to remove it first:"
    echo "  conda env remove -n DAYOA"
    echo ""
    usage
fi

# Check if the shell is bash
if [[ "$SHELL" != "/bin/bash" ]]; then
    echo "Warning: This script is designed to work with bash."
    echo "Your current shell is $SHELL. Proceeding, but compatibility is not guaranteed."
    sleep 2
fi

# Set the script directory
SCRIPT_DIR=config/day/
echo "Path to environment working directory is $SCRIPT_DIR"

# Create .parallel directory if it doesn't exist
mkdir -p "$HOME/.parallel"

# Function to install Miniconda
install_miniconda() {
    echo "No conda environment detected."
    echo "Installing Miniconda to $CONDA_DIR"

    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/Miniconda3.sh
    bash /tmp/Miniconda3.sh -b -p "$CONDA_DIR"
    rm /tmp/Miniconda3.sh

    source "$CONDA_DIR/etc/profile.d/conda.sh"
    conda init bash
    source "$HOME/.bashrc"
    conda activate

    echo "Conda installation complete."
    
}

# Detect or install conda
if command -v conda &> /dev/null; then
    CONDA_DIR="$(dirname "$(dirname "$(which conda)")")"
    echo "Conda detected at $CONDA_DIR"
else
    CONDA_DIR="$HOME/miniconda3"
    install_miniconda
fi

# Ensure conda is initialized
source "$CONDA_DIR/etc/profile.d/conda.sh"

install_mermaid_cli() {
    echo "Installing Mermaid CLI for DAYOA pipeline diagram rendering: $DAYOA_MERMAID_CLI_PACKAGE"
    conda activate "$DY_ENVNAME" || {
        echo "Failed to activate $DY_ENVNAME before Mermaid CLI installation."
        return 1
    }
    export PATH="$CONDA_PREFIX/bin:$PATH"
    if [[ -z "${CONDA_PREFIX:-}" ]]; then
        echo "CONDA_PREFIX is not set after activating $DY_ENVNAME."
        return 1
    fi
    if [[ ! -x "$CONDA_PREFIX/bin/npm" ]]; then
        echo "npm is missing from $DY_ENVNAME; installing nodejs from conda-forge."
        conda install -y -n "$DY_ENVNAME" -c conda-forge nodejs || {
            echo "Failed to install nodejs into $DY_ENVNAME."
            return 1
        }
        conda activate "$DY_ENVNAME" || {
            echo "Failed to reactivate $DY_ENVNAME after nodejs installation."
            return 1
        }
        export PATH="$CONDA_PREFIX/bin:$PATH"
    fi
    "$CONDA_PREFIX/bin/npm" install --global --prefix "$CONDA_PREFIX" "$DAYOA_MERMAID_CLI_PACKAGE" || {
        echo "Failed to install $DAYOA_MERMAID_CLI_PACKAGE."
        return 1
    }
    if [[ ! -x "$CONDA_PREFIX/bin/mmdc" ]]; then
        echo "mmdc was not installed into $DY_ENVNAME at $CONDA_PREFIX/bin/mmdc."
        return 1
    fi
    "$CONDA_PREFIX/bin/mmdc" --version >/dev/null || {
        echo "mmdc is installed but failed to execute."
        return 1
    }
}

#conda install -y conda=25.5.1

# Update Conda Config
conda config --add channels conda-forge
conda config --add channels bioconda

conda config --set channel_priority strict || echo 'Failed to set conda priority to strict'
conda config --set repodata_threads 10 || echo 'Failed to set repodata_threads'
conda config --set verify_threads 4 || echo 'Failed to set verify_threads'
conda config --set execute_threads 4 || echo 'Failed to set execute_threads'
conda config --set always_yes yes || echo 'Failed to set always_yes'
conda config --set default_threads 10 || echo 'Failed to set default_threads'
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Check if the DAYOA environment already exists
if conda env list | grep -q "^$DY_ENVNAME\s"; then
    echo ""
    echo "It appears you have a DAYOA environment already."
    echo "Ensuring required DAYOA npm tools are installed."
    install_mermaid_cli || return 1
    return 0
else
    conda install -y -n base -c conda-forge yq || echo 'Failed to install yq'
    echo "Installing DAYOA environment..."
    # Create the DAYOA environment
    if conda env create -n "$DY_ENVNAME" -f "$SCRIPT_DIR/day.yaml"; then
        echo "DAYOA environment created successfully."
        install_mermaid_cli || return 1
        echo ""
        echo "Try the following commands to get started:"
        echo "  source dyinit --project <PROJECT>"
        echo "  dy-a local"
        echo "  dy-r help"
    else
        echo "Failed to create DAYOA environment."
        return 1
    fi
fi

echo ""
echo "Installation complete."
echo "Please log out and log back in, then run:"
echo "  source dyinit --project <PROJECT>"
echo "  dy-a local"
echo "  dy-r help"

return 0
