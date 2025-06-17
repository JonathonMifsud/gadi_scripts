#!/bin/bash

############################################################################################################
# Script Name: mafft_align_and_trimal_worker.sh
# Description: Aligns sequences with MAFFT and trims with TrimAl using Singularity wrappers.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Load Config from Job File
# ----------------------------------------

job_config="${JOB_CONFIG:?Must provide JOB_CONFIG via -v}"

# shellcheck source=/dev/null
source "$job_config"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ----------------------------------------
# Setup Directories
# ----------------------------------------

log_date=$(date +%Y%m%d)
base_dir="/scratch/${ROOT_PROJECT}/${USER_ID}/${PROJECT_NAME}"
log_dir="${base_dir}/logs"
mkdir -p "$log_dir"

filename=$(basename "$sequences")
cd "$(dirname "$sequences")" || exit 1

# ----------------------------------------
# MAFFT Strategy Warning (for large alignments)
# ----------------------------------------

if echo "$MAFFT_ARGS" | grep -Eq -- '--(einsi|ginsi|linsi|genafpair)'; then
  seq_count=$(grep -c '^>' "$sequences")
  max_len=$(awk '/^>/ {next} {if (length > max) max = length} END {print max}' "$sequences")

  echo "Input FASTA: $filename"
  echo "Sequence count: $seq_count"
  echo "Longest sequence length: $max_len"

  if { [[ "$seq_count" -gt 125 && "$max_len" -gt 5000 ]] || [[ "$seq_count" -gt 250 && "$max_len" -gt 1000 ]]; }; then
    echo "WARNING: This alignment may be too large for the selected MAFFT strategy ($MAFFT_ARGS)."
    echo "Consider faster alternatives: --retree 2 --maxiterate 0 or --parttree"
  fi
fi

# ----------------------------------------
# Run MAFFT
# ----------------------------------------

echo "Running MAFFT with: $MAFFT_ARGS"

tmp_mafft_out=$(mktemp "${filename}_tmp_mafft.XXXX.fasta")
log_file="${log_dir}/${filename}_mafft.log"

# Run MAFFT and capture both stdout and stderr separately
run_mafft.sh mafft $MAFFT_ARGS "$sequences" > "$tmp_mafft_out" 2> "$log_file"

# Sanity check: ensure FASTA format (at least one > header)
if ! grep -q "^>" "$tmp_mafft_out"; then
  echo "❌ ERROR: Alignment not loaded: \"$tmp_mafft_out\" Check the file's content." >&2
  cat "$log_file" >&2
  exit 1
fi

# Save final validated alignment file
mafft_out="${filename}_untrimmed_MAFFT_${log_date}.fasta"
mv "$tmp_mafft_out" "$mafft_out"

# ----------------------------------------
# Run TrimAl for each mode
# ----------------------------------------

IFS=',' read -r -a trim_array <<< "$TRIM_MODES"

for mode in "${trim_array[@]}"; do
  case $mode in
    auto)
      out="${filename}_trimmed_auto_MAFFT_${log_date}.fasta"
      run_trimal.sh trimal -automated1 -in "$mafft_out" -out "$out"
      ;;
    gappyout)
      out="${filename}_trimmed_gappyout_MAFFT_${log_date}.fasta"
      run_trimal.sh trimal -gappyout -in "$mafft_out" -out "$out"
      ;;
    gt*cons*)
      gap=$(echo "$mode" | cut -d':' -f1 | sed 's/^gt//')
      cons=$(echo "$mode" | cut -d':' -f2 | sed 's/^cons//')
      out="${filename}_trimmed_cons${cons}_gt${gap}_MAFFT_${log_date}.fasta"
      run_trimal.sh trimal -gt "$gap" -cons "$cons" -in "$mafft_out" -out "$out"
      ;;
    *)
      echo "ERROR: Unknown trim mode: $mode"
      exit 1
      ;;
  esac
done

echo "Alignment and trimming complete for $filename"
