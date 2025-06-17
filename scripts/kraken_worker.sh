#!/bin/bash
############################################################################################################
# Script Name: kraken_worker.sh
# Description: Worker script for Kraken2 + Bracken + Krona classification on Gadi (paired & single-end)
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the runner script to submit this job via PBS."
  echo ""
fi

# --- Environment variables from runner ---
root_project="${ROOT_PROJECT}"
user="${USER_ID}"
project="${PROJECT_NAME}"
kraken_db="${KRAKEN_DB}"
cpu="${NCPUS_PER_TASK}"

# --- Input parsing ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided."
  exit 1
fi

library_id="$1"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_kraken}"

# --- Directories ---
base_dir="/scratch/${root_project}/${user}/${project}"
trimmed_dir="${base_dir}/trimmed_reads"
out_dir="${base_dir}/kraken"
log_dir="${base_dir}/logs"

mkdir -p "${log_dir}" "${out_dir}"
cd "${trimmed_dir}" || { echo "❌ ERROR: Cannot cd to $trimmed_dir"; exit 1; }

log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec > "${log_file}" 2>&1

# --- Detect read layout ---
layout="unknown"
if [[ -f "${trimmed_dir}/${library_id}_trimmed.fastq.gz" && ! -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    layout="single"
elif [[ -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    layout="paired"
fi

if [[ "$layout" == "unknown" ]]; then
  echo "❌ ERROR: Could not detect read layout for $library_id (single/paired trimmed files not found)"
  exit 1
fi

# --- Validate input files ---
check_file_valid() {
  local file=$1
  if [[ ! -f "$file" ]]; then
    echo "❌ ERROR: File not found: $file"
    exit 1
  fi
  if [[ ! -s "$file" ]]; then
    echo "❌ ERROR: File is empty: $file"
    exit 1
  fi
  if ! gzip -t "$file" &>/dev/null; then
    echo "❌ ERROR: File is corrupted or not a valid gzip: $file"
    exit 1
  fi
}

if [[ "$layout" == "single" ]]; then
  fq="${trimmed_dir}/${library_id}_trimmed.fastq.gz"
  check_file_valid "$fq"
elif [[ "$layout" == "paired" ]]; then
  fq1="${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz"
  fq2="${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz"
  check_file_valid "$fq1"
  check_file_valid "$fq2"
fi

# --- Output paths ---
kraken_output="${out_dir}/${library_id}_kraken_output"
kraken_report="${out_dir}/${library_id}_kraken_report"
bracken_output="${out_dir}/${library_id}.bracken"
bracken_report="${out_dir}/${library_id}.breport"
krona_txt="${out_dir}/${library_id}.b.krona.txt"
krona_html="${out_dir}/${library_id}.b.krona.html"

# --- Run Kraken2 ---
echo "🔎 Running Kraken2 on ${library_id} ($layout-end)"
if [[ "$layout" == "single" ]]; then
  kraken2 --db "$kraken_db" --single "$fq" \
    --output "$kraken_output" --report "$kraken_report" \
    --gzip-compressed --use-names --threads "$cpu"
else
  kraken2 --db "$kraken_db" --paired "$fq1" "$fq2" \
    --output "$kraken_output" --report "$kraken_report" \
    --gzip-compressed --use-names --threads "$cpu"
fi

# --- Run Bracken ---
echo "📊 Running Bracken..."
bracken -d "$kraken_db" -i "$kraken_report" -r 250 -l S -t "$cpu" \
  -o "$bracken_output" -w "$bracken_report"

# --- Generate Krona plot ---
echo "🌈 Generating Krona plot..."
kreport2krona.py -r "$bracken_report" -o "$krona_txt" --no-intermediate-ranks
ktImportText "$krona_txt" -o "$krona_html"

echo "✅ Completed classification for $library_id ($layout-end)"
