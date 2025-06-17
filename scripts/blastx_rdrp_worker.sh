#!/bin/bash

############################################################################################################
# Script Name: blastx_rdrp_worker.sh
# Description: Worker script to run DIAMOND blastx against the RdRp database using a Singularity wrapper.
# Please remember to cite Justine's database paper! https://academic.oup.com/ve/article-abstract/8/2/veac082/6679729
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the run script instead (e.g., ./run_blastx_rdrp.sh) to submit jobs properly via PBS."
  echo ""
fi

# --- Required Variables ---
root_project="${ROOT_PROJECT}"
project="${PROJECT_NAME}"
user=$(whoami)
CPU="${NCPUS_PER_TASK}"
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_blastx}"
rdrp_db="${RDRP_DB:-/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.dmnd}"

# --- Input check ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided to $0."
  exit 1
fi

library_id="$1"
base_dir="/scratch/${root_project}/${user}/${project}"
contig_dir="${base_dir}/contigs/final_contigs"
output_dir="${base_dir}/blast_results"
log_dir="${base_dir}/logs"
input_file="${contig_dir}/${library_id}.contigs.fa"
tempdir="${base_dir}/tmp/diamond_tmp_${library_id}_$RANDOM"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

mkdir -p "$log_dir" "$output_dir" "$tempdir"
cd "$output_dir" || exit 1

log_file="${log_dir}/${jobname}_${log_date}_${library_id}.log"
exec > "$log_file" 2>&1

# --- Validate inputs ---
if [[ ! -f "$input_file" ]]; then
  echo "❌ ERROR: Contig file not found: $input_file"
  exit 1
fi

if [[ ! -f "$rdrp_db" ]]; then
  echo "❌ ERROR: RdRp database not found at $rdrp_db"
  exit 1
fi

echo "🔹 Running DIAMOND blastx on ${library_id}"

# --- Run DIAMOND ---
run_diamond.sh diamond blastx \
  -q "$input_file" \
  -d "$rdrp_db" \
  -t "$tempdir" \
  -o "${output_dir}/${library_id}_rdrp_blastx_results.txt" \
  -e 1E-4 -c2 -k 3 -b 2 -p "$CPU" \
  -f 6 qseqid qlen sseqid stitle pident length evalue \
  --ultra-sensitive

# --- Validate output ---
blast_out="${output_dir}/${library_id}_rdrp_blastx_results.txt"

if [[ ! -f "$blast_out" ]]; then
  echo "❌ ERROR: DIAMOND output file not found: $blast_out"
  exit 1
fi

if [[ ! -s "$blast_out" ]]; then
  echo "⚠️ WARNING: Output is empty — likely no hits for $library_id"
  echo "⚠️ Skipping contig extraction step."
  rm -rf "$tempdir"
  exit 0
fi

# --- Extract Hit Contigs ---
grep -i ".*" "$blast_out" \
  | cut -f1 | sort | uniq > "${output_dir}/${library_id}_temp_contig_names.txt"

grep -A1 -Ff "${output_dir}/${library_id}_temp_contig_names.txt" "$input_file" \
  | sed '/--/d' | sed '/^[[:space:]]*$/d' \
  | sed "/^\>/ s/$/_${library_id}/" > "${output_dir}/${library_id}_rdrp_blastcontigs.fasta"

rm -rf "$tempdir" "${output_dir}/${library_id}_temp_contig_names.txt"

# --- Summary ---
echo "----------------------------------------"
echo "Blastx output: $blast_out"
echo "Filtered contigs: ${output_dir}/${library_id}_rdrp_blastcontigs.fasta"
echo "Output file size: $(du -sh "${output_dir}/${library_id}_rdrp_blastcontigs.fasta")"
echo "----------------------------------------"
echo "✅ Completed DIAMOND blastx for ${library_id}"
