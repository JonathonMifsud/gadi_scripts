#!/bin/bash

############################################################################################################
# Script Name: readcount_worker.sh
# Description: Worker script to count reads from FASTQ files on Gadi with locking for safe parallel writes.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: You appear to be running this script manually."
  echo "Use the runner script to launch jobs via PBS."
fi

# --- Setup Variables ---
user=$(whoami)
project="${PROJECT_NAME}"
root_project="${ROOT_PROJECT}"
CPU="${NCPUS_PER_TASK}"
library_id="$1"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_readcount}"

base_dir="/scratch/${root_project}/${user}/${project}"
trimmed_dir="${base_dir}/trimmed_reads"
log_dir="${base_dir}/logs"
output_dir="${base_dir}/read_count"
output_file="${output_dir}/${project}_accessions_reads.csv"
lock_file="${output_file}.lock"

mkdir -p "$log_dir" "$output_dir"
log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec >"$log_file" 2>&1

# --- Determine layout ---
layout="unknown"
if [[ -f "${trimmed_dir}/${library_id}_trimmed.fastq.gz" ]]; then
  layout="single"
elif [[ -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
  layout="paired"
fi

[[ "$layout" == "unknown" ]] && echo "❌ ERROR: Layout undetectable for $library_id" && exit 1

# --- Read Counting Function (with locking) ---
count_reads() {
  local gz_file="$1"
  local label="$2"

  if ! gzip -t "$gz_file" &>/dev/null; then
    echo "❌ ERROR: Corrupted file: $gz_file"
    return
  fi

  local count
  count=$(gunzip -c "$gz_file" | awk 'END {print NR/4}')

  {
    flock 200
    echo "${label},${count}" >> "$output_file"
  } 200>>"$lock_file"

  echo "✔ Counted reads: ${label}, ${count}"
}

# --- Perform Counting ---
if [[ "$layout" == "single" ]]; then
  count_reads "${trimmed_dir}/${library_id}_trimmed.fastq.gz" "${library_id}_trimmed.fastq"
elif [[ "$layout" == "paired" ]]; then
  count_reads "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" "${library_id}_trimmed_R1.fastq"
  count_reads "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz" "${library_id}_trimmed_R2.fastq"
fi

echo "✅ Completed read count for ${library_id}"
