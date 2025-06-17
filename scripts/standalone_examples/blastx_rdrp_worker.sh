#!/bin/bash

############################################################################################################
# Script Name: blastx_rdrp_worker.sh
# Description: Worker script to run DIAMOND blastx against the RdRp database using a Singularity wrapper.
# Note: Please remember to cite Justine's database paper!
#       https://academic.oup.com/ve/article-abstract/8/2/veac082/6679729
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ------------------------ Manual Execution Warning ------------------------
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: It looks like you are manually executing this worker script."
  echo "Please use the run script instead (e.g., ./run_blastx_rdrp.sh) to submit jobs properly via PBS."
  echo ""
fi

# ------------------------ Environment & Variable Setup ------------------------
# to add to the logs to prevent overwriting
log_date=$(date +%Y%m%d)

# Variables provided by the runner script
CPU="${NCPUS_PER_TASK}"
jobname="${PBS_JOBNAME}"
rdrp_db="${RDRP_DB}"

# ------------------------ Input arguments and Directories ------------------------
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No library ID provided to $0."
  exit 1
fi

library_id="$1"
input_file="${INPUT_DIR}/${library_id}.contigs.fa"
tempdir="${OUTPUT_DIR}/tmp/diamond_tmp_${library_id}_$RANDOM"

# Software path
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# Logging setup
mkdir -p "$LOG_DIR" "$OUTPUT_DIR" "$tempdir"
cd "$OUTPUT_DIR" || exit 1
log_file="${LOG_DIR}/${jobname}_${log_date}_${library_id}.log"
exec > "$log_file" 2>&1

# ------------------------ Input Validation ------------------------
if [[ ! -f "$input_file" ]]; then
  echo "❌ ERROR: Contig file not found: $input_file"
  exit 1
fi

if [[ ! -f "$rdrp_db" ]]; then
  echo "❌ ERROR: RdRp database not found at $rdrp_db"
  exit 1
fi

echo "🔹 Running DIAMOND blastx on ${library_id}"

# ------------------------ Run DIAMOND blastx ------------------------
run_diamond.sh diamond blastx \
  -q "$input_file" \
  -d "$rdrp_db" \
  -t "$tempdir" \
  -o "${OUTPUT_DIR}/${library_id}_rdrp_blastx_results.txt" \
  -e 1E-4 -c2 -k 3 -b 2 -p "$CPU" \
  -f 6 qseqid qlen sseqid stitle pident length evalue \
  --ultra-sensitive


# ------------------------ Post-Processing and Validation ------------------------
blast_out="${OUTPUT_DIR}/${library_id}_rdrp_blastx_results.txt"

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

# ------------------------ Extract Hit Contigs ------------------------
grep -i ".*" "$blast_out" \
  | cut -f1 | sort | uniq > "${OUTPUT_DIR}/${library_id}_temp_contig_names.txt"

grep -A1 -Ff "${OUTPUT_DIR}/${library_id}_temp_contig_names.txt" "$input_file" \
  | sed '/--/d' \
  | sed '/^[[:space:]]*$/d' \
  | sed "/^\>/ s/$/_${library_id}/" \
  > "${OUTPUT_DIR}/${library_id}_rdrp_blastcontigs.fasta"

rm -rf "$tempdir" "${OUTPUT_DIR}/${library_id}_temp_contig_names.txt"


# ------------------------ Summary ------------------------
echo "----------------------------------------"
echo "Blastx output: $blast_out"
echo "Filtered contigs: ${OUTPUT_DIR}/${library_id}_rdrp_blastcontigs.fasta"
echo "Output file size: $(du -sh "${OUTPUT_DIR}/${library_id}_rdrp_blastcontigs.fasta")"
echo "----------------------------------------"
echo "✅ Completed DIAMOND blastx for ${library_id}"