#!/bin/bash

############################################################################################################
# Script Name: bowtie_runner.sh
# Description: Launches a parallel Bowtie2 mapping job using nci-parallel and PBS on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project="myproject"              # Name of project directory under /scratch/<root>/<user>/
root_project="fo27"              # NCI project code
user=$(whoami)

# ----------------------------------------
# Job Configuration
# ----------------------------------------

job_name="bowtie_map"
ncpus=12                         # Total CPUs per PBS job
ncpus_per_task=6                 # CPUs per mapping task (must divide ncpus evenly)
mem="60GB"
walltime="04:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
script_dir="${base_dir}/scripts"
input_base="${base_dir}/mapping"
log_dir="${base_dir}/logs"
task_script="${script_dir}/bowtie_worker.sh"
csv_file=""
log_date=$(date +%Y%m%d)

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /full/path/to/mapping.csv [options]"
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo -e "  $0 -f /full/path/to/mapping.csv [options]"
  echo ""
  echo "This script launches parallel Bowtie2 mapping jobs using PBS on Gadi."
  echo ""
  echo -e "\033[1;34mExpected input CSV format:\033[0m"
  echo "  library_id(s),reference_fasta,min_identity"
  echo ""
  echo "Examples:"
  echo "  SRR123456,some_ref.fasta,0.99"
  echo "  LIB1;LIB2,some_other_ref.fasta,0.99"
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Full path to input CSV file"
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    PBS job name [default: ${job_name}]"
  echo "  -c    Total CPUs per job [default: ${ncpus}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -k    CPUs per task [default: ${ncpus_per_task}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    PBS queue [default: ${queue}]"
  echo "  -r    NCI root project [default: ${root_project}]"
  echo "  -s    Storage string [default: ${storage}]"
  echo "  -n    Number of parallel PBS jobs [default: ${num_jobs}]"
  echo "  -h    Show help"
  echo ""
  echo -e "\033[1;34mExample:\033[0m"
  echo "  $0 -f /scratch/fo27/${user}/${project}/mapping/mapping.csv -n 4"
  echo ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:j:c:m:t:q:r:s:n:k:h" opt; do
  case "$opt" in
    f) csv_file="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    r) root_project="$OPTARG" ;;
    s) storage="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
    k) ncpus_per_task="$OPTARG" ;;
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

if [[ -z "$csv_file" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m CSV file must be provided with -f"
  exit 1
fi

if [[ ! -f "$csv_file" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m CSV file not found: $csv_file"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not found or not executable: $task_script"
  exit 1
fi

mkdir -p "$log_dir"

# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

if (( num_jobs == 1 )); then
  echo -e "\033[34mSubmitting a single PBS job for full input...\033[0m"

  qsub -N "${job_name}_single" \
    -o "${log_dir}/${job_name}_single_${log_date}_pbs.out" \
    -e "${log_dir}/${job_name}_single_${log_date}_pbs.err" \
    -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
    -l storage="$storage" -q "$queue" -P "$root_project" \
    -v input_list="$csv_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task" \
    "${script_dir}/parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched single PBS job for mapping CSV\033[0m"

else
  echo -e "\033[34mSplitting CSV into $num_jobs chunks...\033[0m"
  chunk_dir="${input_base}/chunks_$(basename "$csv_file")_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"

  split -d -n l/$num_jobs "$csv_file" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_jobname="${job_name}_${chunk_name}"

    qsub -N "$chunk_jobname" \
      -o "${log_dir}/${chunk_jobname}_${log_date}_pbs.out" \
      -e "${log_dir}/${chunk_jobname}_${log_date}_pbs.err" \
      -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
      -l storage="$storage" -q "$queue" -P "$root_project" \
      -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task" \
      "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m📦 Submitted $num_jobs chunked PBS jobs.\033[0m"
fi

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

