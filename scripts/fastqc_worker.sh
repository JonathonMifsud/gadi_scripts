#!/bin/bash

############################################################################################################
# Script Name: fastqc_worker.sh
# Description: Worker script to run FastQC on raw/trimmed/unpaired reads using PBS on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Failure at line $LINENO." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: This script should be submitted via PBS using the run script, not run manually."
  echo ""
fi

# --- Input Validation ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No accession provided to $0."
  exit 1
fi

# ----------------------------------------
# Parameters from environment (from qsub -v)
# ----------------------------------------

library_id="$1"
project="${PROJECT_NAME}"
root_project="${ROOT_PROJECT}"
user="${USER_ID}"
types="${READ_TYPES:-raw,trimmed,unpaired}"
CPU="${NCPUS_PER_TASK:-1}"

base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
fastqc_out="${base_dir}/fastqc"
raw_dir="${base_dir}/raw_reads"
trimmed_dir="${base_dir}/trimmed_reads"

mkdir -p "$log_dir" "$fastqc_out"

jobname="${PBS_JOBNAME:-manual_fastqc}"
log_date=$(date +%Y%m%d)
log_file="${log_dir}/fastqc_${jobname}_${log_date}_${library_id}.log"
exec > "$log_file" 2>&1

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ----------------------------------------
# Helper Functions
# ----------------------------------------

check_file_valid() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "⚠️ Skipped missing file: $file"
    return 1
  fi
  if [[ ! -s "$file" ]]; then
    echo "⚠️ Skipped empty file: $file"
    return 1
  fi
  if ! gzip -t "$file" &>/dev/null; then
    echo "❌ ERROR: File is not a valid gzip: $file"
    return 1
  fi
  return 0
}

run_fastqc() {
  local fq="$1"
  check_file_valid "$fq" || return
  echo "🔹 Running FastQC on: $fq"
  run_fastqc.sh fastqc --threads "$CPU" --format fastq --outdir "$fastqc_out" "$fq"
}

detect_layout() {
  if [[ -f "${trimmed_dir}/${library_id}_trimmed.fastq.gz" && ! -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    echo "single"
  elif [[ -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    echo "paired"
  else
    echo "unknown"
  fi
}

# ----------------------------------------
# Detect Layout
# ----------------------------------------

layout=$(detect_layout)

if [[ "$layout" == "unknown" ]]; then
  echo "❌ ERROR: Could not determine read layout for $library_id"
  exit 1
else
  echo "📌 Detected layout: $layout"
fi

IFS='|' read -ra type_arr <<< "$READ_TYPES"
if [[ "${#type_arr[@]}" -eq 0 ]]; then
  echo "❌ ERROR: No read types specified. Exiting."
  exit 1
fi
echo "📋 Read types to process: ${type_arr[*]}"

# ----------------------------------------
# Process each read type
# ----------------------------------------

for type in "${type_arr[@]}"; do
  echo "➡️ Processing type: $type"

  case "$type" in
    raw)
      if [[ "$layout" == "single" ]]; then
        run_fastqc "${raw_dir}/${library_id}.fastq.gz"
      elif [[ "$layout" == "paired" ]]; then
        run_fastqc "${raw_dir}/${library_id}_1.fastq.gz"
        run_fastqc "${raw_dir}/${library_id}_2.fastq.gz"
      fi
      ;;
    trimmed)
      if [[ "$layout" == "single" ]]; then
        run_fastqc "${trimmed_dir}/${library_id}_trimmed.fastq.gz"
      elif [[ "$layout" == "paired" ]]; then
        run_fastqc "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz"
        run_fastqc "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz"
      fi
      ;;
    unpaired)
      if [[ "$layout" == "single" ]]; then
        run_fastqc "${trimmed_dir}/${library_id}_unpaired.fastq.gz"
      elif [[ "$layout" == "paired" ]]; then
        run_fastqc "${trimmed_dir}/${library_id}_unpaired_R1.fastq.gz"
        run_fastqc "${trimmed_dir}/${library_id}_unpaired_R2.fastq.gz"
      fi
      ;;
    *)
      echo "⚠️ Unknown type specified: $type. Skipping."
      ;;
  esac
done

echo "✅ Completed FastQC for $library_id [layout=$layout, types=$types]"
