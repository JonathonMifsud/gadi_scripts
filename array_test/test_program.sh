#!/bin/bash

library_id="$1"
log_date=$(date +%d%m%Y)
script_name=$(basename "$0")
script_base="${script_name%.*}"

# Define output files
work_dir="/scratch/fo27/jm8761/para_test"
out_file="${work_dir}/${library_id}.txt"
log_file="${script_base}_${library_id}_${log_date}.log"

# 🔥 Redirect all output
exec > "$log_file" 2>&1

echo "===== ${script_name} started for ${library_id} ====="
echo "Start time: $(date)"
echo "Working directory: $(pwd)"
echo "Output file: $out_file"
echo

echo "Generating random numbers..."
for i in $(seq 1 100000); do
    printf "%010d\n" "$RANDOM" >> "$out_file"
done

echo
echo "Analysis complete for ${library_id}"
echo "Output written to: ${out_file}"
echo "End time: $(date)"
echo "===== DONE ====="
