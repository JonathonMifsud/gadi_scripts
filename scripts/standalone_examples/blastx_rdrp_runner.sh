#!/bin/bash

############################################################################################################
# Script Name: blastx_rdrp_runner.sh
# Description: Launches DIAMOND blastx jobs against the RdRp database using nci-parallel and PBS on Gadi.
# Please remember to cite Justine's database paper! https://academic.oup.com/ve/article-abstract/8/2/veac082/6679729
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Job Configuration (PBS settings)
# ----------------------------------------
# This section defines the job parameters and variables for this and the worker script.
# THIS IS THE SECTION YOU WILL MOST LIKELY WANT TO MODIFY :) 

# Metadata
root_project="fo27"              # Gadi NCI project code (PBS -P flag)
user=$(whoami)                   # User ID (Automatically pulled from system)

# Resources
# This can all be set here, or using the -c, -k, -m, -t, -q, -p, -r flags when running the script.
ncpus=12                         # Total CPUs requested for a PBS job
ncpus_per_task=6                 # CPUs per individual task
mem="120GB"                       # Memory per PBS job
walltime="12:00:00"              # Max walltime
num_jobs=1                       # Number of PBS jobs to split input into
queue="normal"                   # PBS queue
storage="gdata/${root_project}+scratch/${root_project}" # PBS storage
job_name="blastx_rdrp"           # Base name for PBS jobs

# Paths
# These are nomrally preset but for this stnadalone example, you will need to set them.
input_dir="/scratch/${root_project}/${user}/mytest/contigs/final_contigs/" # Working directory for the job - where the contigs are located
output_dir="/scratch/${root_project}/${user}/standalone_test/blast_results" # Output directory for the job 
script_dir="/scratch/${root_project}/${user}/standalone_test/scripts" # Where the scripts are located
task_script="${script_dir}/blastx_rdrp_worker.sh" # Worker script to run DIAMOND blastx
log_dir="/scratch/${root_project}/${user}/logs" # Where you want the logs to go
rdrp_db="/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.dmnd" # Path to RdRp DIAMOND database

# ----------------------------------------
# Help Functions
# ----------------------------------------

# This function provides a brief usage message when no arguments are provided or -h is used.
# You shouln't need to modify this function unless you are changing the script's usage.

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/accession_lists/setone.txt [options]"
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -f /scratch/${root_project}/${user}/accession_lists/accession_list.txt [options]"
  echo -e ""
  echo "This script launches DIAMOND blastx jobs against the RdRp database using PBS on Gadi."
  echo -e ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Accession list file (one ID per line)"
  echo -e ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -d    Path to RdRp DIAMOND database [default: $rdrp_db]"
  echo "  -j    Job name [default: ${job_name}]"
  echo "  -c    Total CPUs [default: ${ncpus}]"
  echo "  -k    CPUs per task [default: ${ncpus_per_task}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    PBS queue [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Storage resource [default: ${storage}]"
  echo "  -n    Number of PBS jobs [default: ${num_jobs}]"
  echo "  -h    Show this help message"
  echo -e ""
  echo -e "\033[1;34mExample:\033[0m"
  echo -e "  $0 -f /scratch/${root_project}/${user}/accession_lists/mylibs"
  echo -e ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

# This section parses whatever arguments you provide using flags - and sets variables.

while getopts "f:j:c:k:m:t:q:p:r:n:d:h" opt; do
  case $opt in
    f) input_list="$OPTARG" ;; 
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    k) ncpus_per_task="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) storage="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
    d) rdrp_db="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

# This section checks if the required arguments are provided and if the files/directories exist.
if [[ $# -eq 0 ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m No arguments provided."
  brief_help
  exit 1
fi

if [[ -z "${input_list:-}" || ! -f "$input_list" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Accession list not found: $input_list"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script"
  exit 1
fi

if [[ ! -f "$rdrp_db" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m RdRp database not found: $rdrp_db"
  exit 1
fi

mkdir -p "$log_dir"
log_date=$(date +%Y%m%d)

# --- Efficiency Check ---
# This section checks if the number of tasks and CPUs are efficent.
# with Gadi's parallel
num_tasks=$(wc -l < "$input_list")
effective_ncpus=$(( num_tasks * ncpus_per_task ))

if (( effective_ncpus < ncpus )); then
  echo -e "\033[1;33m⚠️ WARNING:\033[0m You requested $ncpus CPUs but only ${effective_ncpus} are used across $num_tasks tasks."
  echo -e "\033[1;33m⚠️ Consider adjusting -c or -k to match task count.\033[0m"
  echo ""
fi

# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

# This section submits the PBS jobs based on the number of tasks and requested CPUs.
# It will assume 1 actual pbs job submission unless the user specifies otherwise.
# If you specify -n 1, it will submit a single job for the full input list.
# If you specify -n > 1, it will split the input list into chunks and submit multiple jobs.
# You really only need to specify -n if there is no chance the number of accessions/libraries
# you have will fit into the max walltime you have requested.

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting a single PBS job for full input list...\033[0m"
  chunk_jobname="${job_name}_single"

  qsub -N "$chunk_jobname" \
    -o "$log_dir/${chunk_jobname}_${log_date}_pbs.out" \
    -e "$log_dir/${chunk_jobname}_${log_date}_pbs.err" \
    -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
    -q "$queue" -P "$root_project" \
    -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RDRP_DB="$rdrp_db",INPUT_DIR="$input_dir",OUTPUT_DIR="$output_dir",LOG_DIR="$log_dir" \
    "${script_dir}/parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched single PBS job: $input_list\033[0m"

else
  echo -e "\033[34m Splitting input list into $num_jobs chunks...\033[0m"
  chunk_dir="$(dirname "$input_list")/chunks_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_jobname="${job_name}_${chunk_name}"

    qsub -N "$chunk_jobname" \
      -o "$log_dir/${chunk_jobname}_${log_date}_pbs.out" \
      -e "$log_dir/${chunk_jobname}_${log_date}_pbs.err" \
      -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
      -q "$queue" -P "$root_project" \
      -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RDRP_DB="$rdrp_db",INPUT_DIR="$input_dir",OUTPUT_DIR="$output_dir",LOG_DIR="$log_dir" \
      "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ All chunked jobs launched under: $chunk_dir\033[0m"
fi

# --- Calculate estimated per-task timeout ---
# This section calculates the estimated timeout for each task based on the walltime and number of tasks.
# You don't need to modify this section unless you want to change how much time is allocated per task inside parrallel 
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
# You not need to modify this section unless you want to change the output format.
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

