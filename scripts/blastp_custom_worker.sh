#!/bin/bash

############################################################################################################
# Script Name: blastp_custom_worker.sh
# Description: DIAMOND blastp worker for user-specified protein inputs/databases on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Job failed at line $LINENO." >&2' ERR

# --- PBS Check ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ ERROR: This script must be run within a PBS job context."
  exit 1
fi

# --- Environment Setup ---
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# --- Variables passed from runner ---
input="${input:?Missing input}"
db="${db:?Missing DIAMOND database}"
outdir="${outdir:?Missing output directory}"
cpus="${NCPUS:-12}"
db_tag="${DB_TAG:-custom}"
diamond_params="${DIAMOND_PARAMS:-"--more-sensitive -e 1e-4 -k 10"}"

# --- Derive output names ---
input_name=$(basename "$input")
prefix="${input_name%.*}_${db_tag}"
result_txt="${outdir}/${prefix}_blastp_results.txt"
result_fa="${outdir}/${prefix}_blastp_contigs.fasta"
temp_ids="${outdir}/${prefix}_temp_ids.txt"
log_file="${outdir}/${prefix}_blastp.log"

# --- Start logging ---
exec >"$log_file" 2>&1
echo "📌 Running DIAMOND blastp on: $input"
echo "🧪 DB: $db_tag"
echo "🔧 CPUs: $cpus"
echo "⚙️  Params: $diamond_params"

# --- Run DIAMOND blastp ---
run_diamond.sh diamond blastp \
  -q "$input" \
  -d "$db" \
  -o "$result_txt" \
  $diamond_params \
  -p "$cpus" \
  -f 6 qseqid qlen sseqid stitle staxids pident length evalue

# --- Extract matching sequences ---
cut -f1 "$result_txt" | sort -u > "$temp_ids"
grep -A1 -Ff "$temp_ids" "$input" > "$result_fa"

# --- Clean output ---
sed -i 's/--//' "$result_fa"
sed -i '/^[[:space:]]*$/d' "$result_fa"
sed --posix -i "/^>/ s/$/_${db_tag}/" "$result_fa"

rm -f "$temp_ids"

echo "✅ blastp complete:"
echo "  - Table: $result_txt"
echo "  - FASTA: $result_fa"
echo "  - Log:   $log_file"
