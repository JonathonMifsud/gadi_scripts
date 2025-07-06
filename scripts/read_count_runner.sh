#!/bin/bash

############################################################################################################
# Script Name: read_count_runner.sh
# Description: Launches a parallel read counting job using nci-parallel and PBS on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project=""
root_project=""
user=$(whoami)

# ----------------------------------------
# PBS Job Configuration
# ----------------------------------------

job_name="readcount"
ncpus=4
ncpus_per_task=1
mem="20GB"
walltime="02:00:00"
num_jobs=1
queue="normal"
storage="scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
script_dir="${base_dir}/scripts"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
task_script="${script_dir}/read_count_worker.sh"
output_dir="${base_dir}/read_count"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/list.txt [options]"
  echo -e "Use \033[1m-h\033[0m for full help."
}

show_help() {
  echo -e ""
  echo -e "\033[1;34mUsage:\033[0m"
  echo -e "  $0 -f accession_list.txt [options]"
  echo -e ""
  echo "This script launches a parallel read counting job using nci-parallel and PBS on Gadi."
  echo -e ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Accession list file (absolute or relative to accession_lists/)"
  echo -e ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    Job name [default: ${job_name}]"
  echo "  -c    Total CPUs per job [default: ${ncpus}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -k    CPUs per task [default: ${ncpus_per_task}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    Queue name [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -n    Number of parallel jobs [default: ${num_jobs}]"
  echo "  -h    Show this help message"
  echo -e ""
  echo -e "\033[1;34mExamples:\033[0m"
  echo -e "\033[32m  Submit a single job:\033[0m"
  echo "    $0 -f list.txt"
  echo -e "\033[32m  Submit 4 parallel jobs:\033[0m"
  echo "    $0 -f list.txt -n 4"
  echo -e ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:j:c:m:k:t:q:p:n:h" opt; do
  case $opt in
    f) input_list="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    k) ncpus_per_task="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
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

if [[ -z "${input_list:-}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing -f input list."
  brief_help
  exit 1
fi

input_list="${input_list/#\~/$HOME}"
[[ "$input_list" != /* ]] && input_list="${input_base}/${input_list}"
[[ ! -f "$input_list" ]] && echo -e "\033[1;31m❌ ERROR:\033[0m File not found: $input_list" && exit 1
[[ ! -x "$task_script" ]] && echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script" && exit 1

mkdir -p "$log_dir" "$output_dir"
log_date=$(date +%Y%m%d)

# ----------------------------------------
# Submit Jobs
# ----------------------------------------

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting a single PBS job...\033[0m"

  qsub -N "${job_name}_single" \
    -o "$log_dir/${job_name}_${log_date}_pbs.out" \
    -e "$log_dir/${job_name}_${log_date}_pbs.err" \
    -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
    -l storage="$storage" -q "$queue" -P "$root_project" \
    -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task" \
    "${script_dir}/parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched a single PBS job for accession list: $input_list\033[0m"

else
  echo -e "\033[34m Splitting input list into $num_jobs chunks...\033[0m"
  chunk_dir="${input_base}/chunks_$(basename "$input_list")_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_jobname="${job_name}_${chunk_name}"

    qsub -N "$chunk_jobname" \
         -o "$log_dir/${chunk_jobname}_${log_date}_pbs.out" \
         -e "$log_dir/${chunk_jobname}_${log_date}_pbs.err" \
         -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
         -l storage="$storage" -q "$queue" -P "$root_project" \
         -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task" \
         "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ Submitted $num_jobs PBS jobs from chunks under: $chunk_dir\033[0m"
fi

# ----------------------------------------
# Summary
# ----------------------------------------

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
