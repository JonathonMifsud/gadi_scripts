#!/bin/bash

############################################################################################################
# Script Name: download_sra_worker.sh
# Author: JCO Mifsud jonathon.mifsud1@gmail.com
# Description: Worker script to download SRA data using Kingfisher.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail

# --- Define paths ---
root_project="${ROOT_PROJECT}"
user=$(whoami) 
project="${PROJECT_NAME}"

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the run script instead (e.g., ./${project}_download_sra_run.sh) to submit jobs properly via PBS."
  echo ""
fi

# --- Input check ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided to $0."
  exit 1
fi

library_id="$1"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME}"

base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
raw_dir="${base_dir}/raw_reads"

mkdir -p "$raw_dir" "$log_dir"
cd "$raw_dir" || exit 1

log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec > "$log_file" 2>&1

# --- Modules and paths ---
module load aspera/4.4.1
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

echo "▶️ Downloading: $library_id (Job: $jobname)"

run_kingfisher.sh kingfisher get -r "$library_id" \
  -m ena-ascp ena-ftp prefetch aws-http aws-cp \
  --force --prefetch-max-size 100000000 \
  --output-format-possibilities fastq.gz fastq

# Handle single-end files
if [[ -f "$library_id.fastq" || -f "$library_id.sra.fastq" ]]; then
  gzip -c "$library_id.fastq" > "$library_id.fastq.gz" 2>/dev/null || \
  gzip -c "$library_id.sra.fastq" > "$library_id.fastq.gz"
  rm -f "$library_id.fastq" "$library_id.sra.fastq"
fi

# Handle paired-end files
if [[ -f "${library_id}_1.fastq" || -f "${library_id}.sra_1.fastq" ]]; then
  gzip -c "${library_id}_1.fastq" > "${library_id}_1.fastq.gz" 2>/dev/null || \
  gzip -c "${library_id}.sra_1.fastq" > "${library_id}_1.fastq.gz"
  gzip -c "${library_id}_2.fastq" > "${library_id}_2.fastq.gz" 2>/dev/null || \
  gzip -c "${library_id}.sra_2.fastq" > "${library_id}_2.fastq.gz"
  rm -f "${library_id}_1.fastq" "${library_id}_2.fastq" "${library_id}.sra_"*.fastq
fi

# Fix corrupt gzipped files
for f in "${library_id}"*.gz; do
  if ! gzip -t "$f"; then
    mv "$f" "${f}.corrupt"
    gzip -c "${f}.corrupt" > "$f"
    gzip -t "$f" || rm -f "$f"
  fi
done

# Cleanup temp files
rm -f "${library_id}".aria2* "${library_id}".aspera-ckpt* "${library_id}".partial*

echo "✅ Completed $library_id"
