#!/bin/env bash

ref=$1
cram=$2

echo testview
samtools view -@ 8  -T $ref   $cram | head > /dev/null

echo quickcheck
samtools quickcheck $cram

echo done
