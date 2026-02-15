#!/bin/bash

watch -n 2 "squeue -h -o '%i' | xargs -r -n1 scontrol show job | grep -E 'JobId=|WorkDir='"
