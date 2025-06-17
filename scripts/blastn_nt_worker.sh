#!/bin/bash

############################################################################################################
# Script Name: blastnt_worker.sh
# Description: Concatenates RdRp and RVDB contigs from accessions, runs BLASTN against NT, extracts hits.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# NEED TO ADD THE NEWER PARALLEL OPTIONS (-k and -n) 

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- PBS Context Check ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "❌ ERROR: This script must be run within a PBS job."
  exit 1
fi

# --- Input Variables from Runner ---
root_project="${ROOT_PROJECT}"
project="${PROJECT_NAME}"
user="${USER_ID}"
CPU="${NCPUS_PER_TASK:-24}"
accession_file="${input_list}"
db="${NT_DB}"
param_file="${PARAM_FILE}"

# Validate param file exists
if [[ ! -f "$param_file" ]]; then
  echo "❌ ERROR: Parameter file not found: $param_file"
  exit 1
fi

blast_params=$(<"$param_file")

# --- Directory Setup ---
accession_name=$(basename "${accession_file}" .txt)
base_dir="/scratch/${root_project}/${user}/${project}"
blast_dir="${base_dir}/blast_results"
log_dir="${base_dir}/logs"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

mkdir -p "$blast_dir" "$log_dir"
cd "$blast_dir" || exit 1

# --- Logging Info ---
echo "Starting BLASTN pipeline for accession set: $accession_name"
echo "NT database: $db"
echo "CPU threads: $CPU"
echo "Parameters file: $param_file"
echo "----------------------------------------"
echo "Loaded BLASTN parameters:"
echo "$blast_params"
echo "----------------------------------------"

# --- Step 1: Gather and Concatenate Contigs ---
rdrp_cat="${blast_dir}/${accession_name}_combined_rdrp.fa"
rvdb_cat="${blast_dir}/${accession_name}_combined_rvdb.fa"
combined="${blast_dir}/${accession_name}_blastcontigs_forNT.fa"

rdrp_files=()
rvdb_files=()
missing=()

while IFS= read -r id; do
  rdrp="${blast_dir}/${id}_rdrp_blastcontigs.fasta"
  rvdb="${blast_dir}/${id}_rvdb_blastcontigs.fasta"
  [[ -f "$rdrp" ]] && rdrp_files+=("$rdrp") || missing+=("❌ Missing RdRp: $rdrp")
  [[ -f "$rvdb" ]] && rvdb_files+=("$rvdb") || missing+=("❌ Missing RVDB: $rvdb")
done < "${accession_file}"

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '%s\n' "${missing[@]}"
fi

cat "${rdrp_files[@]}" > "$rdrp_cat"
cat "${rvdb_files[@]}" > "$rvdb_cat"
cat "$rdrp_cat" "$rvdb_cat" > "$combined"
rm "$rdrp_cat" "$rvdb_cat"

# --- Step 2: Run BLASTN ---
blast_out="${blast_dir}/${accession_name}_nt_blastn_results.txt"
echo "Running BLASTN..."
echo "Command: run_blast.sh blastn -query \"$combined\" -db \"$db\" -out \"$blast_out\" -num_threads \"$CPU\" $blast_params"

run_blast.sh blastn \
  -query "$combined" \
  -db "$db" \
  -out "$blast_out" \
  -num_threads "$CPU" \
  $blast_params \
  -outfmt '6 qseqid qlen sacc salltitles staxids pident length evalue'

# --- Step 3: Extract Matching Contigs ---
hit_ids="${blast_dir}/${accession_name}_temp_nt_contig_names.txt"
output_fa="${blast_dir}/${accession_name}_nt_blastcontigs.fasta"

cut -f1 "$blast_out" | sort | uniq > "$hit_ids"
grep -A1 -Ff "$hit_ids" "$combined" > "$output_fa"

# --- Final Cleanup and Annotation ---
sed -i 's/--//' "$output_fa"
sed -i '/^[[:space:]]*$/d' "$output_fa"
sed --posix -i "/^\>/ s/$/"_$accession_name"/" "$output_fa"

rm "$hit_ids" "$combined"
rm -f "$param_file"

echo "Completed BLASTN search for: $accession_name"
echo "Final output: $output_fa"
