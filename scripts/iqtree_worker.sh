#!/bin/bash

############################################################################################################
# Script Name: iqtree_worker.sh
# Description: Runs IQ-TREE on an alignment with robust checks and metadata logging.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

job_config="${JOB_CONFIG:?Must provide JOB_CONFIG via -v}"
source "$job_config"

# ----------------------------------------
# Environment Context (PBS + User Vars)
# ----------------------------------------

alignment="${alignment:?Must provide alignment via env variable}"
model="${model:-MFP}"
user="${USER_ID:-$(whoami)}"
project="${PROJECT_NAME:-unknown}"
root_project="${ROOT_PROJECT:-fo27}"
extra_args="${IQTREE_EXTRA_ARGS:-}"
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ----------------------------------------
# Derived Paths and Filenames
# ----------------------------------------

log_date=$(date +%Y%m%d)
base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
mkdir -p "$log_dir"

aln_base=$(basename "$alignment")
prefix="${aln_base%.*}_${model}_${log_date}"
cd "$(dirname "$alignment")" || exit 1

# ----------------------------------------
# Execution Notice
# ----------------------------------------

if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "WARNING: This script appears to be running outside of PBS context."
fi

echo "PBS Job Name: ${PBS_JOBNAME:-unknown}"
echo "PBS Job ID:   ${PBS_JOBID:-none}"

aln_id=$(basename "$alignment" | sed 's/\.[^.]*$//' | sed 's/[^A-Za-z0-9._-]/_/g')
jobtag="${PBS_JOBNAME:-iqtree}_${aln_id}_${log_date}"
echo "Job Tag: $jobtag"

echo "Running IQ-TREE on: ${aln_base}"
echo "Model: ${model}"
[[ -n "$extra_args" ]] && echo "Extra Args: ${extra_args}"

# ----------------------------------------
# Run IQ-TREE via Singularity Wrapper
# ----------------------------------------

run_iqtree.sh iqtree2 \
  -s "$alignment" \
  -m "$model" \
  -bb 1000 -alrt 1000 \
  --prefix "$prefix" \
  -nt AUTO --safe \
  $extra_args

# ----------------------------------------
# Output Validation
# ----------------------------------------

if [[ ! -s "${prefix}.treefile" ]]; then
  echo "ERROR: Tree file was not generated or is empty: ${prefix}.treefile"
  exit 1
fi

if [[ "$model" == "MFP" && ! -s "${prefix}.log" ]]; then
  echo "ERROR: Log file not found or empty for model extraction: ${prefix}.log"
  exit 1
fi

# ----------------------------------------
# Metadata Extraction
# ----------------------------------------

best_model="N/A"
data_type="unknown"

if [[ -f "${prefix}.log" ]]; then
  best_model=$(grep "Best-fit model:" "${prefix}.log" | awk -F ':' '{print $2}' | xargs || true)
  data_type=$(grep "Data type:" "${prefix}.log" | awk -F ':' '{print $2}' | xargs || true)
fi

meta_file="${prefix}.meta.txt"
{
  echo "Input File: $alignment"
  echo "Run Date: $(date)"
  echo "Model Supplied: $model"
  echo "Best-fit Model: $best_model"
  echo "Data Type: $data_type"
  echo "User: $user"
  echo "Project: $project"
  echo "Host: $(hostname)"
  [[ -n "$extra_args" ]] && echo "Extra Args: $extra_args"
} > "$meta_file"

# ----------------------------------------
# Final Summary
# ----------------------------------------

echo "Completed IQ-TREE run"
echo "Tree file: ${prefix}.treefile"
echo "Log file:  ${prefix}.log"
echo "Metadata:  ${meta_file}"
[[ "$model" == "MFP" ]] && echo "Best-fit model: ${best_model}"
echo "Alignment type: ${data_type}"
