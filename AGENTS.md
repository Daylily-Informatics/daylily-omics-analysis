# AWS CREDENTIALS
Ask user for profile name to set AWS_PROFILE to, never use default as profile name.

# UPON STARTING A NEW TERMINAL SESSION ON A MAC
On a mac, no workflows will actually ever be run, but we need the conda env for the dy-cli to work to debug and tinker locally.  This repo must be deployed to an AWS ParallelCluster headnode which has been configured by `daylily-ephemeral-cluster`, and each analysis workset is run from a clone of this repo (or reruns).

# TERMINAL STARTUP (ALWAYS RUN THESE COMMANDS IN THIS ORDER)
## ON A MAC 
Always `conda activate DAY-EC`, little is done in this repo from a mac, but most dependencies needed to tinker and debug are in the daylily-ephemeral-cluster env DAY-EC.

## ON THE HEADNODE (ubuntu)
- Intended use via is brokered by daylily-ephemeral-cluster, often via the GUI daylily-ursa. 
- CLONE REPO USING `day-clone` (which should be in the login bash PATH). See the day-clone --help for more info (and the .md docs).
- upon moving to reso cloned dir (the analysis dir):
  - INITIALIZE: source the `dyoainit` script to initialize the dy-cli. (note: the output of dyoainit should tell you how to activte slurm or local execution env, set genome build, run example commands.
  - ACTIVATE: `dy-a local hg38` to activate the local execution env, or  `dy-a slurm hg38` to activate the slurm execution env. Note, the second argument is the genome build, and must be set. In practice, this is almost always `hg38`, but could be `b37` or `hg38_broad`. 
  - RUN: `dy-r help` to see the available targets, and the init output should tell you how to run the common workflow. Important flags: -n for dry run, -p to print helpful info to stdout, -j for job limit (local should be 1 or 2, slurm can be 300-500), -k to keep going if a job fails... the dy-r cli command actually composes a complex snakemake command given these user command line specified ones. Run `dy-r --help` for all of them.
   
# Debugging From MAC
If given an AWS_PROFILE, region, cluster name, pem file, and optionally the : path to analysis, and potentially a tmux session analysis is running in. With the `DAY-EC` env actice, you can use `pcluster describe-cluster -n <name> --region <region>` to get the cluster headnode ip, and can then ssh into it using ssh -i <pemfile> ubuntu@<headnode-ip>.  

