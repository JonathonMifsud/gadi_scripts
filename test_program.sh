#!/bin/bash

wd=/scratch/fo27/jm8761/para_test
library_id=$1
outfile="$wd/""$library_id".txt

for i in $(seq 1 100000); do
    printf "%010d\n" "$RANDOM" >> "$outfile"
done
