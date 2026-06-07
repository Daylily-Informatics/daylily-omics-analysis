SMN12 resource files copied from the pinned SMNCopyNumberCaller repository tag
`v0.0.0.4-jem`.

The upstream script `smn_caller.py` resolves resources relative to
`dirname(__file__)/data`, but the pinned package does not install those data
files beside the script in the conda environment. The DayOA rule runs the script
from a temporary wrapper directory and symlinks this directory as `data`.
