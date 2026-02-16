#!/bin/bash

watch squeue  -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R %Z"
