#!/bin/bash

############################################################################################################
# Script Name: assemble_reads_worker.sh
# Description: Worker script to assemble reads using MEGAHIT on Gadi HPC system.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the run script instead (e.g., ./yourproject_assemble_reads_worker.sh) to submit jobs properly via PBS."
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
trimmed_dir="${base_dir}/trimmed_reads"
contig_dir="${base_dir}/contigs"
log_dir="${base_dir}/logs"
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

mkdir -p "${trimmed_dir}" "${log_dir}" "${contig_dir}/final_contigs" "${contig_dir}/final_logs"
cd "${trimmed_dir}" || exit 1

log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec > "${log_file}" 2>&1

# --- Detect read layout (single or paired-end) ---
layout="unknown"
if [[ -f "${trimmed_dir}/${library_id}_trimmed.fastq.gz" && ! -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    layout="single"
elif [[ -f "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" ]]; then
    layout="paired"
fi

if [[ "${layout}" == "unknown" ]]; then
  echo "❌ ERROR: Could not detect layout for ${library_id} (single/paired trimmed read files not found)"
  exit 1
fi

# --- Validate trimmed read files ---

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

# --- Run Assembly ---
# Remove previous MEGAHIT output if present
if [[ -d "${contig_dir}/${library_id}_out" ]]; then
  echo "⚠️ WARNING: Output directory already exists: ${contig_dir}/${library_id}_out"
  echo "🧹 Removing old directory to avoid MEGAHIT failure..."
  echo "For safety I don't use the continue option, if you want to try this remove the line below and add the continue option to the MEGAHIT command."
  rm -rf "${contig_dir}/${library_id}_out"
fi

if [[ "${layout}" == "single" ]]; then
  echo "🔹 Single-end de novo assembly..."
  run_megahit.sh megahit --num-cpu-threads "${CPU}" \
            --memory 0.9 \
            -r "${trimmed_dir}/${library_id}_trimmed.fastq.gz" \
            -o "${contig_dir}/${library_id}_out"

elif [[ "${layout}" == "paired" ]]; then
  echo "🔹 Paired-end de novo assembly..."
  run_megahit.sh megahit --num-cpu-threads "${CPU}" \
            --memory 0.9 \
            -1 "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" \
            -2 "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz" \
            -o "${contig_dir}/${library_id}_out"
fi


if [[ ! -s "${contig_dir}/${library_id}_out/final.contigs.fa" ]]; then
  echo "❌ ERROR: MEGAHIT did not produce a final contigs file or it is empty."
  exit 1
fi

cat "${contig_dir}"/"${library_id}"_out/final.contigs.fa | sed "s/=//g" | sed "s/ /_/g" > "${contig_dir}"/final_contigs/"${library_id}".contigs.fa
cp "${contig_dir}"/"${library_id}"_out/log "${contig_dir}"/final_logs/"${library_id}"_megahit.log
echo "Basic MEGAHIT assembly stats:"
echo "----------------------------------------"
echo "Final contigs file: ${contig_dir}/final_contigs/${library_id}.contigs.fa"
tail -n 2 "${contig_dir}"/final_logs/"${library_id}"_megahit.log
echo "----------------------------------------"
echo "Contig file size: $(du -sh "${contig_dir}"/final_contigs/"${library_id}".contigs.fa)"
echo "----------------------------------------"
rm -r "${contig_dir}"/"${library_id}"_out

echo "✅ Completed assembly for ${library_id}"