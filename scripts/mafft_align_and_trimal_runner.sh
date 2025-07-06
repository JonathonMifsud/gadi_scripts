#!/bin/bash

############################################################################################################
# Script Name: mafft_align_and_trim_runner.sh
# Description: Submits a PBS job to align sequences with MAFFT and trim with TrimAl using user-defined options.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project=""
root_project=""
user=$(whoami)

# ----------------------------------------
# PBS Job Config
# ----------------------------------------

job_name="align_trim"
ncpus=6
mem="24GB"
walltime="04:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
script_dir="${base_dir}/scripts"
task_script="${script_dir}/mafft_align_and_trimal_worker.sh"
mkdir -p "$log_dir"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\nUsage: $0 -i /path/to/sequences.fasta [options]"
  echo -e "\nFor full help: $0 -h"
}

show_help() {
  echo ""
  echo "Usage:"
  echo "  $0 -i sequences.fasta [options]"
  echo ""
  echo "Aligns sequences using MAFFT and trims using TrimAl"
  echo ""
  echo "Required:"
  echo "  -i    Full path to input FASTA file (unaligned sequences)"
  echo ""
  echo "Options:"
  echo "  -a    MAFFT arguments (quoted). Default: \"--genafpair --maxiterate 1000\""
  echo "  -t    Trim modes (comma-separated). Default: \"gappyout,gt0.9:cons10,gt0.9:cons30,gt0.9:cons50\""
  echo "  -j    PBS job name [default: ${job_name}]"
  echo "  -c    CPUs to request [default: ${ncpus}]"
  echo "  -m    Memory to request [default: ${mem}]"
  echo "  -q    Queue [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Root project path [default: ${root_project}]"
  echo "  -h    Show this help message"
  echo ""
  exit 1
}

# ----------------------------------------
# Defaults
# ----------------------------------------

mafft_args="--genafpair --maxiterate 1000"
trim_modes="gappyout,gt0.9:cons10,gt0.9:cons30,gt0.9:cons50"

# ----------------------------------------
# Parse Arguments
# ----------------------------------------

while getopts "i:a:t:j:c:m:q:p:r:h" opt; do
  case $opt in
    i) input_fasta="$OPTARG" ;;
    a) mafft_args="$OPTARG" ;;
    t) trim_modes="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) root_project="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ $# -eq 0 ]]; then
  echo "ERROR: No arguments provided."
  brief_help
  exit 1
fi

if [[ -z "${input_fasta:-}" ]]; then
  echo "ERROR: Missing required -i argument."
  brief_help
  exit 1
fi

if [[ ! -f "$input_fasta" ]]; then
  echo "ERROR: Input FASTA file not found: $input_fasta"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo "ERROR: Worker script not executable: $task_script"
  exit 1
fi

log_date=$(date +%Y%m%d)
fasta_base=$(basename "$input_fasta")
jobtag="${job_name}_${fasta_base%.*}_${log_date}"
job_config="${log_dir}/${jobtag}.jobvars"

# ----------------------------------------
# Write job variables to file
# ----------------------------------------

cat > "$job_config" <<EOF
sequences="$input_fasta"
MAFFT_ARGS="$mafft_args"
TRIM_MODES="$trim_modes"
USER_ID="$user"
PROJECT_NAME="$project"
ROOT_PROJECT="$root_project"
EOF

# ----------------------------------------
# Submit PBS Job
# ----------------------------------------

qsub -N "$jobtag" \
  -o "${log_dir}/${jobtag}.out" \
  -e "${log_dir}/${jobtag}.err" \
  -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
  -l storage="$storage" \
  -q "$queue" -P "$root_project" \
  -v "JOB_CONFIG=$job_config" \
  "$task_script"

echo "Submitted PBS job: $jobtag"

# --- Calculate estimated per-task timeout ---
IFS=: read -r hh mm ss <<< "$walltime"
total_walltime_secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))
num_ranks=$(( ncpus / ncpus_per_task ))

# Full list estimation
num_waves_full=$(( (num_tasks + num_ranks - 1) / num_ranks ))
timeout_full=$(( total_walltime_secs * 95 / 100 / num_waves_full ))
timeout_full_fmt=$(printf '%02d:%02d:%02d' $((timeout_full / 3600)) $(( (timeout_full % 3600) / 60 )) $((timeout_full % 60)))

# Estimate timeout per chunk (if split into multiple jobs)
avg_chunk_tasks=$(( (num_tasks + num_jobs - 1) / num_jobs ))
waves_per_chunk=$(( (avg_chunk_tasks + num_ranks - 1) / num_ranks ))
timeout_chunk=$(( total_walltime_secs * 95 / 100 / waves_per_chunk ))
timeout_chunk_fmt=$(printf '%02d:%02d:%02d' $((timeout_chunk / 3600)) $(( (timeout_chunk % 3600) / 60 )) $((timeout_chunk % 60)))

# --- Final Job Configuration Summary ---
echo -e "\nPBS Job Configuration Summary:"
printf "   Accession tasks total:        %s\n" "$num_tasks"
printf "   Parallel MPI ranks:           %s (ncpus / ncpus_per_task)\n" "$num_ranks"
printf "   Total CPUs per job:           %s\n" "$ncpus"
printf "   CPUs per task:                %s\n" "$ncpus_per_task"
printf "   Memory per job:               %s\n" "$mem"
printf "   Walltime per job:             %s\n" "$walltime"
printf "   Number of PBS jobs:           %s\n" "$num_jobs"
if (( num_jobs == 1 )); then
  printf "   Estimated task waves:         %s (tasks ÷ ranks)\n" "$num_waves_full"
  printf "   Timeout per task:             %s seconds (~%s)\n" "$timeout_full" "$timeout_full_fmt"
else
  printf "   Estimated avg tasks/chunk:    %s\n" "$avg_chunk_tasks"
  printf "   Estimated task waves/chunk:   %s\n" "$waves_per_chunk"
  printf "   Timeout per task (per chunk): %s seconds (~%s)\n" "$timeout_chunk" "$timeout_chunk_fmt"
  echo ""
  echo "Note: Each PBS job will calculate its own optimized timeout based on its chunk size."
fi

