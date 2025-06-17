#!/bin/bash

############################################################################################################
# Script Name: blastx_rvdb_worker.sh
# Description: Worker script to run DIAMOND blastx against the RVDB protein database using Singularity.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Manual Execution Warning
# ----------------------------------------

if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: This script is meant to be run via PBS using the runner script."
  echo ""
fi

# ----------------------------------------
# Required Environment Variables
# ----------------------------------------

root_project="${ROOT_PROJECT:?❌ ROOT_PROJECT not defined}"
project="${PROJECT_NAME:?❌ PROJECT_NAME not defined}"
user=$(whoami)
CPU="${NCPUS_PER_TASK:?❌ NCPUS_PER_TASK not defined}"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_blastx}"
rvdb_db="${RVDB_DB:-}"

# ----------------------------------------
# Input Argument
# ----------------------------------------

if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided."
  exit 1
fi

library_id="$1"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
contig_dir="${base_dir}/contigs/final_contigs"
output_dir="${base_dir}/blast_results"
log_dir="${base_dir}/logs"
input_file="${contig_dir}/${library_id}.contigs.fa"
tempdir="${base_dir}/tmp/diamond_tmp_${library_id}_$RANDOM"
log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"

export PATH="/g/data/${root_project}/software/singularity/bin:$PATH"

mkdir -p "$log_dir" "$output_dir" "$tempdir"
cd "$output_dir" || exit 1
exec > "$log_file" 2>&1

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ ! -f "$input_file" ]]; then
  echo "❌ ERROR: Contig file not found: $input_file"
  exit 1
fi

if [[ -z "$rvdb_db" || ! -f "$rvdb_db" ]]; then
  echo "❌ ERROR: RVDB DIAMOND database not provided or not found."
  echo "Please pass it with -d to the runner script."
  echo "Expected format: /g/data/fo27/databases/blast/rvdb/rvdb_prot_v<ver>_<month>/rvdb_prot_v<ver>_<month>.dmnd"
  exit 1
fi

echo "🔹 Running DIAMOND blastx for ${library_id}"

# ----------------------------------------
# Run DIAMOND
# ----------------------------------------

run_diamond.sh diamond blastx \
  -q "$input_file" \
  -d "$rvdb_db" \
  -t "$tempdir" \
  -o "${output_dir}/${library_id}_rvdb_blastx_results.txt" \
  -e 1E-10 -c1 -k 1 -p "$CPU" \
  -f 6 qseqid qlen sseqid stitle staxids pident length evalue \
  --ultra-sensitive --iterate

blast_out="${output_dir}/${library_id}_rvdb_blastx_results.txt"

if [[ ! -f "$blast_out" ]]; then
  echo "❌ ERROR: DIAMOND output not found."
  exit 1
fi

if [[ ! -s "$blast_out" ]]; then
  echo "⚠️ WARNING: Output is empty (no hits)."
  rm -rf "$tempdir"
  exit 0
fi

# ----------------------------------------
# Extract Contigs
# ----------------------------------------

grep -i ".*" "$blast_out" | cut -f1 | sort | uniq > "${output_dir}/${library_id}_temp_contig_names.txt"

grep -A1 -Ff "${output_dir}/${library_id}_temp_contig_names.txt" "$input_file" \
  | sed '/--/d' | sed '/^[[:space:]]*$/d' \
  | sed "/^\>/ s/$/_${library_id}/" > "${output_dir}/${library_id}_rvdb_blastcontigs.fasta"
  
rm -rf "$tempdir" "${output_dir}/${library_id}_temp_contig_names.txt"

# ----------------------------------------
# Summary
# ----------------------------------------

echo "----------------------------------------"
echo "Blastx output: $blast_out"
echo "Filtered contigs: ${output_dir}/${library_id}_rvdb_blastcontigs.fasta"
echo "Output size: $(du -sh "${output_dir}/${library_id}_rvdb_blastcontigs.fasta")"
echo "----------------------------------------"
echo "✅ Completed DIAMOND blastx for ${library_id}"
