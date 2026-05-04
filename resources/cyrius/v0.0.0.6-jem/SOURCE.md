Cyrius v0.0.0.6-jem resources
==============================

These data files were copied from the Cyrius source tree used by the workflow
environment:

- Repository: https://github.com/iamh2o/Cyrius
- Requested revision: v0.0.0.6-jem
- Commit: d52ec2ba4204fad8ff0705d4cde80f9e97567d74
- Source path: Cyrius/data

The installed `star_caller.py` script resolves resources relative to the script
path, but the pip install used by this environment does not install the data
directory next to the console script. The workflow rule links this vendored data
into a per-job runtime directory before invoking Cyrius.
