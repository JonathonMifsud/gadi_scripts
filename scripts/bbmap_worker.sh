#!/bin/bash

############################################################################################################
# Script Name: bbmap_worker.sh
# Description: Worker script to run BBMap mapping for one entry from the mapping CSV on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Environment Variables (passed via qsub -v)
# ----------------------------------------

project="${PROJECT}"
root_project="${ROOT_PROJECT}"
input_csv="${CSV_PATH}"
user="${USER}"
array_index="${PBS_ARRAY_INDEX:-0}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
trimmed_dir="${base_dir}/trimmed_reads"
mapping_dir="${base_dir}/mapping"
reference_dir="${mapping_dir}/reference"
log_dir="${base_dir}/logs"
mkdir -p "$mapping_dir" "$log_dir"

# ----------------------------------------
# Parse CSV Line
# Format: library_id,reference_fasta,min_identity
# ----------------------------------------

IFS=',' read -r library_id reference_fasta minid <<< "$(sed -n "$((array_index + 1))p" "$input_csv")"

if [[ -z "$library_id" || -z "$reference_fasta" || -z "$minid" ]]; then
  echo "❌ ERROR: Invalid line at index $array_index. Check format of $input_csv"
  exit 1
fi

log_date=$(date +%Y%m%d)
log_prefix="${log_dir}/bbmap_${library_id}_${log_date}"
exec > "${log_prefix}.log" 2>&1

echo -e "📌 Mapping job for:\n - Library ID(s): $library_id\n - Reference: $reference_fasta\n - Identity: $minid"
echo "----------------------------------------"

# ----------------------------------------
# Validate Reference File
# ----------------------------------------

ref_path="${reference_dir}/${reference_fasta}"
if [[ ! -f "$ref_path" ]]; then
  echo "❌ ERROR: Reference file not found: $ref_path"
  exit 1
fi

# ----------------------------------------
# Detect Layout & Validate Inputs
# ----------------------------------------

fq1="${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz"
fq2="${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz"
fq_single="${trimmed_dir}/${library_id}_trimmed.fastq.gz"

layout="unknown"

check_file_valid() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "❌ ERROR: File not found: $file"
    exit 1
  fi
  if [[ ! -s "$file" ]]; then
    echo "❌ ERROR: File is empty: $file"
    exit 1
  fi
  if ! gzip -t "$file" &>/dev/null; then
    echo "❌ ERROR: Invalid or corrupted gzip file: $file"
    exit 1
  fi
}

if [[ -f "$fq_single" && ! -f "$fq1" ]]; then
  layout="single"
  check_file_valid "$fq_single"
elif [[ -f "$fq1" && -f "$fq2" ]]; then
  layout="paired"
  check_file_valid "$fq1"
  check_file_valid "$fq2"
else
  echo "❌ ERROR: Could not detect layout or missing trimmed read files for $library_id"
  exit 1
fi

echo "📎 Detected layout: $layout"
echo "----------------------------------------"

# ----------------------------------------
# Output Filenames
# ----------------------------------------

safe_lib_id=$(echo "$library_id" | sed 's/;/_/g')
out_prefix="${mapping_dir}/${safe_lib_id}_${reference_fasta}_${minid}"
fq_out="${out_prefix}_mapped.fq"
sam_out="${out_prefix}_mapped.sam"
bam_script="${out_prefix}_bamscript.sh"
stats_out="${out_prefix}_bbmap_stats.txt"
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ----------------------------------------
# Run BBMap
# ----------------------------------------

echo "🚀 Running BBMap..."
if [[ "$layout" == "paired" ]]; then
  run_bbmap.sh bbmap.sh \
    in1="$fq1" \
    in2="$fq2" \
    ref="$ref_path" \
    minid="$minid" \
    vslow nodisk qtrim=lr \
    outm="$fq_out" \
    out="$sam_out" \
    bamscript="$bam_script"
else
  run_bbmap.sh bbmap.sh \
    in="$fq_single" \
    ref="$ref_path" \
    minid="$minid" \
    vslow nodisk qtrim=lr \
    outm="$fq_out" \
    out="$sam_out" \
    bamscript="$bam_script"
fi

# ----------------------------------------
# Run BAM Script & Generate Stats
# ----------------------------------------

echo "🧬 Sorting & indexing..."
bash "$bam_script"

echo "📊 Generating pileup stats..."
run_bbmap.sh pileup.sh in="$sam_out" out="$stats_out"

# ----------------------------------------
# Final Output Summary
# ----------------------------------------

echo "✅ BBMap completed for $library_id"
echo "Mapped SAM: $sam_out"
echo "Stats file: $stats_out"
echo "----------------------------------------"
