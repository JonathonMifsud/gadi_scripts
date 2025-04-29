#!/bin/bash

################################################################################
# Script Name: prostt5_run.sh
# Author: JCO Mifsud
# Description: Submits ProstT5 AA2fold prediction PBS jobs on Gadi (CPU or GPU).
#
# ----------------------------------------
# Setup Notes:
#
# 1. Singularity Container:
#    - Container used: pytorch_2.1.0-cuda11.8-cudnn8-runtime.sif
#    - Location: /g/data/fo27/software/singularity/images/pytorch_2.1.0-cuda11.8-cudnn8-runtime.sif
#    - This container provides Python 3.10 + PyTorch 2.1 for running ProstT5.
#
# 2. Inside Container - Install Transformers:
#    module load singularity
#    singularity shell /g/data/fo27/software/singularity/images/pytorch_2.1.0-cuda11.8-cudnn8-runtime.sif
#    pip install --user transformers sentencepiece
#
#    (This installs Huggingface Transformers and SentencePiece into user space.)
#
# 3. ProstT5 Model Files:
#    - ProstT5 model files were downloaded manually from Huggingface:
#      https://huggingface.co/Rostlab/ProstT5
#    - Stored locally under: /g/data/fo27/models/prostT5/
#    - No internet access required during jobs; models are loaded from local folder.
#
# 4. GPU Resource Requirements:
#    - When device=cuda, you MUST request:
#         ncpus=12
#         ngpus=1
#      (Due to Gadi gpuvolta queue requirements: 12 CPUs per GPU.)
#    - Queue is automatically switched to gpuvolta if device=cuda.
#
# 5. Expected Workflow:
#    - prostt5_run.sh submits the job
#    - prostt5_worker.pbs loads Singularity, runs container
#    - prostt5_predict.py runs inside the container and predicts 3Di structure
#
# 6. Troubleshooting:
#    - If error "No module named 'transformers'" appears:
#      Ensure you have pip installed transformers inside the container (Step 2).
#
################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Early Defaults
# ----------------------------------------

device="cpu"  # Default device
ncpus=""
mem=""
queue=""
walltime="02:00:00"
job_name="prostt5_predict"
root_project="fo27"
project="mytest"
storage="gdata/${root_project}+scratch/${root_project}"
user=$(whoami)

base_dir="/scratch/${root_project}/${user}/${project}"

# Important paths
log_dir="${base_dir}/logs"
script_dir="${base_dir}/scripts"
other_scripts_dir="${script_dir}/other_scripts"
python_script="${other_scripts_dir}/prostt5_predict.py"
pbs_script="${other_scripts_dir}/prostt5_worker.pbs"

# Create necessary folders if missing
mkdir -p "${log_dir}"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -i /full/path/to/input.fasta -o /full/path/to/output.fasta [options]"
  echo ""
  echo "For full help, use: $0 -h"
}

show_help() {
  echo ""
  echo -e "\033[1;34mProstT5 AA2fold Prediction Launcher - Help\033[0m"
  echo ""
  echo "This script submits a PBS job to predict 3D structural features from amino acid sequences"
  echo "using the ProstT5 model inside a Singularity container on the NCI Gadi HPC system."
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -i    Full absolute path to input FASTA file"
  echo "  -o    Full absolute path to output FASTA file"
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    PBS Job name [default: ${job_name}]"
  echo "  -c    Number of CPUs [auto: 4 for CPU, 12 for GPU]"
  echo "  -m    Memory requested [auto: 32GB]"
  echo "  -t    Walltime (hh:mm:ss) [default: ${walltime}]"
  echo "  -q    Queue to submit to (default depends on device)"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -d    Device to use (cpu or cuda) [default: ${device}]"
  echo "  -h    Show this help message and exit"
  echo ""
  exit 1
}

# ----------------------------------------
# Parse Full Arguments
# ----------------------------------------

OPTIND=1
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

if [[ ! -f "$input_fasta" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Input FASTA file not found: $input_fasta"
  exit 1
fi

# ----------------------------------------
# Set Device Defaults
# ----------------------------------------

if [[ "$device" == "cuda" ]]; then
  [[ -z "$ncpus" ]] && ncpus=12  # Gadi gpuvolta requires 12 CPUs per GPU
  [[ -z "$mem" ]] && mem="32GB"
  [[ -z "$queue" ]] && queue="gpuvolta"
else
  [[ -z "$ncpus" ]] && ncpus=4
  [[ -z "$mem" ]] && mem="32GB"
  [[ -z "$queue" ]] && queue="normal"
fi

# Validate device and queue combo
if [[ "$device" == "cuda" && "$queue" == "normal" ]]; then
  queue="gpuvolta"
  echo -e "\033[33m[INFO]\033[0m Auto-switching to GPU queue: ${queue}"
fi

if [[ "$device" == "cpu" && "$queue" =~ gpu.* ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m CPU jobs cannot be submitted to GPU queues (${queue})"
  exit 1
fi

# ----------------------------------------
# PBS Resource flags
# ----------------------------------------

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
     -v INPUT_FASTA="${input_fasta}",OUTPUT_FASTA="${output_fasta}",DEVICE="${device}",PROJECT="${project}",SCRIPT_PATH="${python_script}" \
     "${pbs_script}"

echo -e "\033[32m✅ Submitted ProstT5 prediction job: ${job_name} to queue: ${queue}\033[0m"
