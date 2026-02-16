#!/bin/bash


watch -n 2 squeue -o \"%.8i %.10P %.29j %.8u %.2t %.10M %.4C %.10m %.6Q %.8p %R %Z\"
