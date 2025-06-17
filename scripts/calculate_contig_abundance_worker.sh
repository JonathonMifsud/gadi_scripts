#!/bin/bash

############################################################################################################
# Script Name: abundance_reads_worker.sh
# Description: Worker script to estimate abundance using RSEM on Gadi HPC system.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# ----------------------------------------------------------------------------------
# NOTE: Why we don't use Singularity for RSEM 
# ----------------------------------------------------------------------------------
# Although there is a container available for both Trinity and RSEM that can be used
# We are a little weird in that we use the support script align_and_estimate_abundance.pl
# to run Trinity with RSEM and Bowtie2.
# Neither Trinity nor RSEM have everything we need in their containers to run this
# and binding the binaries from one image to the path of the other
# leads to a bunch of issues with the perl library.
#
# As Gadi has Trinity and Bowtie2 modules
# and we have installed RSEM into a shared directory /g/data/fo27/software/other_software/rsem
# we can use these directly without the need for a container.
# ----------------------------------------------------------------------------------

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: You are manually executing this script. Use a PBS run script instead."
fi

# --- Load required modules ---
module load trinity/2.12.0
module load bowtie2/2.3.5.1
module load samtools/1.19

# --- Define paths ---
root_project="${ROOT_PROJECT}"
user=$(whoami)
project="${PROJECT_NAME}"
CPU="${NCPUS_PER_TASK}"
CLEANUP=true

base_dir="/scratch/${root_project}/${user}/${project}"
trimmed_dir="${base_dir}/trimmed_reads"
contig_dir="${base_dir}/contigs/final_contigs"
abundance_dir="${base_dir}/abundance"
log_dir="${base_dir}/logs"
RSEM_BIN_DIR="/g/data/fo27/software/other_software/rsem"

export PATH="${RSEM_BIN_DIR}:$PATH"

# --- Setup working directories ---
mkdir -p "${abundance_dir}/final_abundance" "${log_dir}"
cd "${trimmed_dir}" || exit 1

# --- Input check ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided."
  exit 1
fi

library_id="$1"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_abundance}"
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
  echo "❌ ERROR: Cannot determine read layout for ${library_id}."
  exit 1
fi

# --- Validate input files ---
check_file_valid() {
  local file="$1"
  if [[ ! -f "$file" || ! -s "$file" ]]; then
    echo "❌ ERROR: Invalid or missing input file: $file"
    exit 1
  fi
}
check_file_valid "${contig_dir}/${library_id}.contigs.fa"
[[ "$layout" == "single" ]] && check_file_valid "${trimmed_dir}/${library_id}_trimmed.fastq.gz"
[[ "$layout" == "paired" ]] && check_file_valid "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz"
[[ "$layout" == "paired" ]] && check_file_valid "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz"

# --- Run Trinity with local RSEM + bowtie2 support ---
abundance_outdir="${abundance_dir}/${library_id}_abundance"

if [[ "$layout" == "single" ]]; then
  echo "🔹 Running single-end RSEM estimation..."
   /apps/trinity/2.12.0/util/align_and_estimate_abundance.pl \
    --transcripts "${contig_dir}/${library_id}.contigs.fa" \
    --seqType fq \
    --single "${trimmed_dir}/${library_id}_trimmed.fastq.gz" \
    --est_method RSEM \
    --aln_method bowtie2 \
    --output_dir "${abundance_outdir}" \
    --thread_count "$CPU" \
    --prep_reference
else
  echo "🔹 Running paired-end RSEM estimation..."
   /apps/trinity/2.12.0/util/align_and_estimate_abundance.pl \
    --transcripts "${contig_dir}/${library_id}.contigs.fa" \
    --seqType fq \
    --left "${trimmed_dir}/${library_id}_trimmed_R1.fastq.gz" \
    --right "${trimmed_dir}/${library_id}_trimmed_R2.fastq.gz" \
    --est_method RSEM \
    --aln_method bowtie2 \
    --output_dir "${abundance_outdir}" \
    --thread_count "$CPU" \
    --prep_reference
fi

# --- Validate output ---
rsem_result="${abundance_outdir}/RSEM.isoforms.results"
if [[ ! -f "$rsem_result" || ! -s "$rsem_result" ]]; then
  echo "❌ ERROR: RSEM output file is missing or empty."
  exit 1
fi

firstline=$(head -n 1 "$rsem_result" || echo "")
if [[ "$firstline" != *"transcript_id"* ]]; then
  echo "❌ ERROR: RSEM output file has unexpected header: $firstline"
  exit 1
fi

# --- Finalize results ---
cp "${rsem_result}" "${abundance_dir}/final_abundance/${library_id}_RSEM.isoforms.results"

# --- Cleanup ---
cleanup_files() {
  echo "🧹 Cleaning up..."
  rm -f "${abundance_outdir}/bowtie2.bam" || true
  rm -f "${contig_dir}/${library_id}.contigs.fa."* || true
}
[[ "$CLEANUP" == true ]] && cleanup_files

echo "✅ Successfully completed abundance estimation for ${library_id}"
