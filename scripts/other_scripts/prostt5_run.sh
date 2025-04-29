#!/bin/bash

################################################################################
# Script Name: prostt5_run.sh
# Author: JCO Mifsud
# Description: Submits ProstT5 AA2fold prediction PBS jobs on Gadi (CPU or GPU).
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Early Defaults (device only)
# ----------------------------------------

device="cpu"  # Default to CPU

# ----------------------------------------
# Pre-parse Device Argument
# ----------------------------------------

while getopts "d:" opt; do
  case $opt in
    d) device="$OPTARG" ;;
  esac
done

# Set dynamic defaults based on device
if [[ "$device" == "cuda" ]]; then
  ncpus=4
  mem="32GB"
  queue="gpuvolta"
else
  ncpus=4
  mem="32GB"
  queue="normal"
fi

walltime="02:00:00"
job_name="prostt5_predict"
root_project="your_root_project_code"   # <-- set this
project="your_project_name"              # <-- set this
storage="gdata/${root_project}+scratch/${root_project}"
user=$(whoami)

# Update base_dir properly
base_dir="/scratch/${root_project}/${user}/${project}"

# Important paths
prostt5_dir="${base_dir}/prostt5"
log_dir="${base_dir}/logs"
venv_path="${base_dir}/venvs/prostt5_env"
script_dir="${base_dir}/scripts"
other_scripts_dir="${script_dir}/other_scripts"
python_script="${script_dir}/prostt5_predict.py"
pbs_script="${script_dir}/prostt5_worker.pbs"

# Create necessary folders if missing
mkdir -p "${prostt5_dir}" "${log_dir}"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -i input.fasta -o output.fasta [options]"
  echo ""
  echo "For full help, use: $0 -h"
}

show_help() {
  echo ""
  echo -e "\033[1;34mProstT5 AA2fold Prediction Launcher - Help\033[0m"
  echo ""
  echo "This script submits a PBS job to predict 3D structural features from amino acid sequences"
  echo "using the ProstT5 model on the NCI Gadi HPC system."
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -i    Input FASTA filename (relative to ${prostt5_dir})"
  echo "  -o    Output FASTA filename (relative to ${prostt5_dir})"
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    PBS Job name [default: ${job_name}]"
  echo "  -c    Number of CPUs [default: ${ncpus}]"
  echo "  -m    Memory requested [default: ${mem}]"
  echo "  -t    Walltime (hh:mm:ss) [default: ${walltime}]"
  echo "  -q    Queue to submit to (default depends on device: normal or gpuvolta)"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -d    Device to use (cpu or cuda) [default: ${device}]"
  echo "  -h    Show this help message and exit"
  echo ""
  echo -e "\033[1;34mPaths:\033[0m"
  echo "  - Inputs/outputs under: ${prostt5_dir}"
  echo "  - Logs under: ${log_dir}"
  echo ""
  echo -e "\033[1;34mExamples:\033[0m"
  echo "  bash $0 -i myinput.fasta -o myoutput_predicted.fasta"
  echo "  bash $0 -i myinput.fasta -o myoutput_predicted.fasta -d cuda"
  echo ""
  exit 1
}

# ----------------------------------------
# Parse Full Arguments
# ----------------------------------------

OPTIND=1  # Reset option parsing
while getopts "i:o:j:c:m:t:q:p:d:h" opt; do
  case $opt in
    i) input_fasta="$OPTARG" ;;
    o) output_fasta="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG"; storage="gdata/${root_project}+scratch/${root_project}" ;;
    d) device="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ $# -eq 0 ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m No arguments provided."
  brief_help
  exit 1
fi

if [[ -z "${input_fasta:-}" || -z "${output_fasta:-}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m -i and -o arguments are required."
  brief_help
  exit 1
fi

if [[ ! -f "${prostt5_dir}/${input_fasta}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Input FASTA not found: ${prostt5_dir}/${input_fasta}"
  exit 1
fi

# --- Validate device/queue combo ---
if [[ "$device" == "cuda" ]]; then
  if [[ "$queue" == "normal" ]]; then
    queue="gpuvolta"
    echo -e "\033[33m[INFO]\033[0m Device is CUDA but normal queue specified. Auto-switching to ${queue}."
  fi
else
  if [[ "$queue" =~ gpu.* ]]; then
    echo -e "\033[1;31m❌ ERROR:\033[0m CPU job cannot be submitted to GPU queue (${queue})."
    exit 1
  fi
fi

# --- PBS Resource flags ---
pbs_resources="-l ncpus=${ncpus} -l mem=${mem} -l walltime=${walltime} -l storage=${storage}"

if [[ "$device" == "cuda" ]]; then
  pbs_resources="${pbs_resources} -l ngpus=1"
fi

# ----------------------------------------
# Submit PBS Job
# ----------------------------------------

log_date=$(date +%Y%m%d_%H%M%S)

qsub -N "$job_name" \
     -o "${log_dir}/${job_name}_${log_date}.out" \
     -e "${log_dir}/${job_name}_${log_date}.err" \
     -q "${queue}" -P "${root_project}" \
     ${pbs_resources} \
     -v INPUT_FASTA="${prostt5_dir}/${input_fasta}",OUTPUT_FASTA="${prostt5_dir}/${output_fasta}",DEVICE="${device}",PROJECT="${project}",VENV_PATH="${venv_path}",SCRIPT_PATH="${python_script}" \
     "${pbs_script}"

echo -e "\033[32m✅ Submitted ProstT5 prediction job: ${job_name} to queue: ${queue}\033[0m"
