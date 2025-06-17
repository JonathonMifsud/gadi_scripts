#!/bin/bash

############################################################################################################
# Script Name: trim_reads_worker.sh
# Description: Worker script to trim reads using Trimmomatic on Gadi HPC system.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the run script instead (e.g., ./yourproject_download_sra_run.sh) to submit jobs properly via PBS."
  echo ""
fi

# --- Define paths ---
root_project="${ROOT_PROJECT}"
user=$(whoami) 
project="${PROJECT_NAME}"
CPU="${NCPUS_PER_TASK}"


# --- Input check ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided to $0."
  exit 1
fi

library_id="$1"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_trim}"

base_dir="/scratch/${root_project}/${user}/${project}"
raw_dir="${base_dir}/raw_reads"
trimmed_dir="${base_dir}/trimmed_reads"
log_dir="${base_dir}/logs"
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

mkdir -p "$raw_dir" "$trimmed_dir" "$log_dir"
cd "$raw_dir" || exit 1

log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec > "$log_file" 2>&1

# Adapter files location
adapter_single="${base_dir}/adapters/TruSeq3-SE.fa"
adapter_paired="${base_dir}/adapters/joint_TruSeq3_Nextera-PE.fa"

# --- Detect read layout (single or paired-end) ---
layout="unknown"
if [[ -f "${raw_dir}/${library_id}.fastq.gz" && ! -f "${raw_dir}/${library_id}_1.fastq.gz" ]]; then
    layout="single"
elif [[ -f "${raw_dir}/${library_id}_1.fastq.gz" ]]; then
    layout="paired"
fi

if [[ "$layout" == "unknown" ]]; then
  echo "❌ ERROR: Could not detect layout for $library_id (single/paired files not found)."
  exit 1
fi

echo "▶️ Trimming reads for $library_id (layout: $layout) (Job: $jobname)"

# --- Run Trimming ---
if [[ "$layout" == "single" ]]; then
  echo "🔹 Single-end trimming..."
  cp "$adapter_single" ./ || echo "⚠️ Could not copy adapter file, continuing if available."
  
  run_trimmomatic.sh trimmomatic SE -threads "$CPU" -phred33 \
    "${raw_dir}/${library_id}.fastq.gz" \
    "${trimmed_dir}/${library_id}_trimmed.fastq.gz" \
    ILLUMINACLIP:$(basename "$adapter_single"):2:30:10 \
    SLIDINGWINDOW:4:5 LEADING:5 TRAILING:5 MINLEN:25

elif [[ "$layout" == "paired" ]]; then
  echo "🔹 Paired-end trimming..."
  cp "$adapter_paired" ./ || echo "⚠️ Could not copy adapter file, continuing if available."
  
  run_trimmomatic.sh trimmomatic PE -threads "$CPU" -phred33 \
    "${raw_dir}/${library_id}_1.fastq.gz" "${raw_dir}/${library_id}_2.fastq.gz" \
    "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" "${trimmed_dir}/${library_id}_unpaired_R1.fastq.gz" \
    "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz" "${trimmed_dir}/${library_id}_unpaired_R2.fastq.gz" \
    ILLUMINACLIP:$(basename "$adapter_paired"):2:30:10 \
    SLIDINGWINDOW:4:5 LEADING:5 TRAILING:5 MINLEN:25
fi

check_file_valid() {
  local file=$1
  if [[ ! -f "${file}" ]]; then
    echo "❌ ERROR: Expected file not found: ${file}"
    exit 1
  fi
  if [[ ! -s "${file}" ]]; then
    echo "❌ ERROR: File is empty: ${file}"
    exit 1
  fi
  if ! gzip -t "${file}" &>/dev/null; then
    echo "❌ ERROR: File is corrupted or not a valid gzip: ${file}"
    exit 1
  fi
}

if [[ "${layout}" == "single" ]]; then
  check_file_valid "${trimmed_dir}/${library_id}_trimmed.fastq.gz"
elif [[ "${layout}" == "paired" ]]; then
  check_file_valid "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz"
  check_file_valid "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz"
fi

echo "✅ Completed trimming for $library_id"
