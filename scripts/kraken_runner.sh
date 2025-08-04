#!/bin/bash
############################################################################################################
# Script Name: kraken_runner.sh
# Description: Gadi launcher for Kraken2+Bracken+Krona classification of trimmed reads
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# Lauren's verison has been tested more so please consider using that one:

set -euo pipefail
trap 'echo "❌ ERROR: Failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata 
# ----------------------------------------
# Project name for organizational purposes (under /scratch)
project=""
# Gadi NCI project code (PBS -P flag)
root_project=""
# User ID (Automatically pull username on Gadi)
user=$(whoami)

# ----------------------------------------
# Job Configuration
# ----------------------------------------
job_name="kraken_classify"
ncpus=12
mem="30GB"
walltime="06:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}+gdata/fo27+scratch/fo27" # Storage resource requirements for PBS job (gdata, scratch)
db_path="/g/data/${root_project}/databases/kraken_db"

script_dir="/scratch/${root_project}/${user}/${project}/scripts"
base_dir="/scratch/${root_project}/${user}/${project}"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
task_script="${script_dir}/${project}_kraken_worker.sh"

mkdir -p "$log_dir"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\nUsage: $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]\n"
  echo "FIX ME!!!! It assumes the database is /g/data/${root_project}/databases/kraken_db"
  echo "For full help, use: $0 -h"
}

show_help() {
  echo -e "\nUsage: $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]\n"
  echo "This script launches Kraken2+Bracken+Krona classification jobs on Gadi."
  echo -e "\nRequired:"
  echo "  -f    Accession list file path or filename in accession_lists/"
  echo -e "\nOptions:"
  echo "  -j    Job name [default: $job_name]"
  echo "  -c    Number of CPUs [default: $ncpus]"
  echo "  -m    Memory per job [default: $mem]"
  echo "  -t    Walltime [default: $walltime]"
  echo "  -q    Queue [default: $queue]"
  echo "  -p    NCI project code [default: $root_project]"
  echo "  -r    Storage flags [default: $storage]"
  echo "  -n    Number of PBS jobs [default: $num_jobs]"
  echo "  -d    Kraken database path [default: $db_path]"
  echo "  -h    Show this help message"
  echo -e "\nExample:\n  $0 -f mylibs.txt -n 4"
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------
while getopts "f:j:c:m:t:q:p:r:n:d:h" opt; do
  case $opt in
    f)
      input_list="${OPTARG}"
      [[ "$input_list" != /* ]] && input_list="${input_base}/${input_list}"
      ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) storage="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
    d) db_path="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------
if [[ -z "${input_list:-}" || ! -f "$input_list" ]]; then
  echo "❌ ERROR: Input list not found: $input_list"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo "❌ ERROR: Worker script not found or not executable: $task_script"
  exit 1
fi

log_date=$(date +%Y%m%d)
chunk_dir="${input_base}/chunks_$(basename "$input_list")_${job_name}_${log_date}"

# ----------------------------------------
# Job Submission
# ----------------------------------------
if (( num_jobs == 1 )); then
  qsub -N "${job_name}_single" \
    -o "$log_dir/${job_name}_single_${log_date}.out" \
    -e "$log_dir/${job_name}_single_${log_date}.err" \
    -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
    -l storage="$storage" -q "$queue" -P "$root_project" \
    -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",KRAKEN_DB="$db_path" \
    "${script_dir}/${project}_parallel_task_launcher.pbs"

else
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    qsub -N "${job_name}_${chunk_name}" \
      -o "$log_dir/${job_name}_${chunk_name}_${log_date}.out" \
      -e "$log_dir/${job_name}_${chunk_name}_${log_date}.err" \
      -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
      -l storage="$storage" -q "$queue" -P "$root_project" \
      -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",KRAKEN_DB="$db_path" \
      "${script_dir}/${project}_parallel_task_launcher.pbs"
  done
fi

# --- Calculate estimated per-task timeout ---
# IFS=: read -r hh mm ss <<< "$walltime"
# total_walltime_secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))
# num_ranks=$(( ncpus / ncpus_per_task ))

# Full list estimation
# num_waves_full=$(( (num_tasks + num_ranks - 1) / num_ranks ))
# timeout_full=$(( total_walltime_secs * 95 / 100 / num_waves_full ))
# timeout_full_fmt=$(printf '%02d:%02d:%02d' $((timeout_full / 3600)) $(( (timeout_full % 3600) / 60 )) $((timeout_full % 60)))

# Estimate timeout per chunk (if split into multiple jobs)
# avg_chunk_tasks=$(( (num_tasks + num_jobs - 1) / num_jobs ))
# waves_per_chunk=$(( (avg_chunk_tasks + num_ranks - 1) / num_ranks ))
# timeout_chunk=$(( total_walltime_secs * 95 / 100 / waves_per_chunk ))
# timeout_chunk_fmt=$(printf '%02d:%02d:%02d' $((timeout_chunk / 3600)) $(( (timeout_chunk % 3600) / 60 )) $((timeout_chunk % 60)))

# --- Final Job Configuration Summary ---
# echo -e "\nPBS Job Configuration Summary:"
# printf "   Accession tasks total:        %s\n" "$num_tasks"
#printf "   Parallel MPI ranks:           %s (ncpus / ncpus_per_task)\n" "$num_ranks"
#printf "   Total CPUs per job:           %s\n" "$ncpus"
#printf "   CPUs per task:                %s\n" "$ncpus_per_task"
#printf "   Memory per job:               %s\n" "$mem"
#printf "   Walltime per job:             %s\n" "$walltime"
#printf "   Number of PBS jobs:           %s\n" "$num_jobs"
#if (( num_jobs == 1 )); then
#  printf "   Estimated task waves:         %s (tasks ÷ ranks)\n" "$num_waves_full"
#  printf "   Timeout per task:             %s seconds (~%s)\n" "$timeout_full" "$timeout_full_fmt"
#else
#  printf "   Estimated avg tasks/chunk:    %s\n" "$avg_chunk_tasks"
#  printf "   Estimated task waves/chunk:   %s\n" "$waves_per_chunk"
#  printf "   Timeout per task (per chunk): %s seconds (~%s)\n" "$timeout_chunk" "$timeout_chunk_fmt"
#  echo ""
#  echo "Note: Each PBS job will calculate its own optimized timeout based on its chunk size."
#fi
