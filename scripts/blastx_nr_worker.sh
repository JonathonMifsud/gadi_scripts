#!/bin/bash

############################################################################################################
# Script Name: blastnr_worker.sh
# Description: Concatenates RdRp and RVDB contigs from accessions, runs DIAMOND blastx against NR, extracts hits.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# NEED TO ADD THE NEWER PARALLEL OPTIONS (-k and -n) 

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- PBS context check ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: This script is intended to be run within a PBS job."
  exit 1
fi

# --- Variables passed from runner ---
root_project="${ROOT_PROJECT}"
project="${PROJECT_NAME}"
user="${USER_ID}"
CPU="${NCPUS_PER_TASK:-24}"
accession_file="${input_list}"
diamond_para="${DIAMOND_PARAMS:-"--more-sensitive -e 1e-4 -b4 -p ${CPU} -k10"}"
db="${NR_DB}"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"


# --- Derived paths ---
accession_name=$(basename "${accession_file}" .txt)
base_dir="/scratch/${root_project}/${user}/${project}"
blast_dir="${base_dir}/blast_results"
log_dir="${base_dir}/logs"
tmpdir="/scratch/${root_project}/${user}/tmp"

mkdir -p "${blast_dir}" "${log_dir}" "${tmpdir}"
cd "${blast_dir}" || exit 1

log_date=$(date +%Y%m%d)
log_file="${log_dir}/blastnr_${log_date}_${accession_name}.log"
exec > "${log_file}" 2>&1

echo "📌 Starting NR blastx pipeline for: ${accession_file}"
echo "🔹 Output directory: ${blast_dir}"
echo "🔹 DIAMOND DB: ${db}"

# --- Step 1: Gather and concatenate contigs ---
rdrp_cat="${blast_dir}/${accession_name}_combined_rdrp.fasta"
rvdb_cat="${blast_dir}/${accession_name}_combined_rvdb.fasta"
combined_all="${blast_dir}/${accession_name}_nr_blastcontigs_forNR.fasta"

rdrp_files=()
rvdb_files=()
missing=()

while IFS= read -r id; do
  r="${blast_dir}/${id}_rdrp_blastcontigs.fasta"
  v="${blast_dir}/${id}_rvdb_blastcontigs.fasta"
  [[ -f "$r" ]] && rdrp_files+=("$r") || missing+=("❌ Missing RdRp: $r")
  [[ -f "$v" ]] && rvdb_files+=("$v") || missing+=("❌ Missing RVDB: $v")
done < "${accession_file}"

# Print missing if any
if [[ ${#missing[@]} -gt 0 ]]; then
  printf '%s\n' "${missing[@]}"
fi

# Concatenate
cat "${rdrp_files[@]}" > "$rdrp_cat"
cat "${rvdb_files[@]}" > "$rvdb_cat"
cat "$rdrp_cat" "$rvdb_cat" > "$combined_all"
rm "$rdrp_cat" "$rvdb_cat"

# --- Step 2: Run DIAMOND blastx ---
blast_out="${blast_dir}/${accession_name}_nr_blastx_results.txt"
echo "🚀 Running DIAMOND blastx..."
run_diamond.sh diamond blastx \
  -q "$combined_all" \
  -d "$db" \
  -o "$blast_out" \
  $diamond_para \
  -f 6 qseqid qlen sseqid stitle staxids pident length evalue \
  --tmpdir "$tmpdir"

# --- Step 3: Extract hits ---
hit_ids="${blast_dir}/${accession_name}_temp_nr_contig_names.txt"
output_fa="${blast_dir}/${accession_name}_nr_blastcontigs.fasta"

cut -f1 "$blast_out" | sort | uniq > "$hit_ids"
grep -A1 -Ff "$hit_ids" "$combined_all" > "$output_fa"

# --- Cleanup and annotate ---
sed -i 's/--//' "$output_fa"
sed -i '/^[[:space:]]*$/d' "$output_fa"
sed --posix -i "/^\>/ s/$/"_$accession_name"/" "$output_fa"

rm "$hit_ids" "$combined_all"

echo "✅ Done. Output: ${output_fa}"