#!/bin/bash

############################################################################################################
# Script Name: download_sra_runner.sh
# Description: Launches a parallel SRA download job using nci-parallel and PBS on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

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
# Job Configuration (PBS settings)
# ----------------------------------------
# you can override these defaults with command line arguments

job_name="download_sra"          # Base name for PBS jobs
ncpus=1                          # Total CPUs requested for a PBS job
ncpus_per_task=1                 # CPUs each individual task should use (must divide evenly into ncpus)
mem="6GB"                        # Total memory requested for the job
walltime="04:00:00"              # Maximum allowed walltime for the PBS job
num_jobs=1                       # Number of PBS jobs to split input into (chunking)
queue="copyq"                    # PBS queue to submit to
storage="gdata/${root_project}+scratch/${root_project}+gdata/fo27+scratch/fo27" # Storage resource requirements for PBS job (gdata, scratch)

# ----------------------------------------
# Paths
# ----------------------------------------

script_dir="/scratch/${root_project}/${user}/${project}/scripts"        # Path to PBS and worker scripts
input_base="/scratch/${root_project}/${user}/${project}/accession_lists" # Path to accession lists
log_dir="/scratch/${root_project}/${user}/${project}/logs"               # Path where job logs will be stored
task_script="${script_dir}/${project}_download_sra_worker.sh"                      # Path to the task worker script

# ----------------------------------------
# Help Function
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone [options]"
  echo -e ""
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e ""
  echo -e "\033[1;34mUsage:\033[0m"
  echo -e "  $0 -f accession_list.txt [options]"
  echo -e ""

  echo "This script launches a parallel SRA download job using nci-parallel and PBS on Gadi."
  echo -e ""

  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Full path to the accession list file (absolute or relative to ${input_base}/"
  echo -e ""

  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    Job name [default: download_sra]"
  echo "  -c    Number of CPUs [default: 1]"
  echo "  -m    Memory per job [default: 6GB]"
  echo "  -t    Walltime [default: 04:00:00]"
  echo "  -q    PBS queue [default: copyq]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Storage resources [default: gdata/${root_project}+scratch/${root_project}]"
  echo "  -n    Number of parallel jobs to run [default: 1]"
  echo "  -h    Show this help message"
  echo -e ""

  echo -e "\033[1;34mExample:\033[0m"
  echo -e "\033[32m  Submit a single PBS job:\033[0m"
  echo -e "    $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone"
  echo -e ""
  echo -e "\033[32m  Submit multiple PBS jobs in parallel (split into 4 chunks):\033[0m"
  echo -e "    $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone -n 4"
  echo -e ""

  echo -e "\033[1;33mNotes:\033[0m"
  echo "  - 'copyq' queue limits to a single CPU per job."
  echo "  - Use the -n option if you want multiple jobs to run in parallel."
  echo -e ""

  echo -e "\033[1;34mGitHub:\033[0m"
  echo "  https://github.com/JonathonMifsud/gadi_scripts"
  echo -e ""

  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:j:c:m:t:q:p:r:n:h" opt; do
  case $opt in
    f)
      if [[ "$OPTARG" = /* ]]; then
        input_list="$OPTARG"
      else
        input_list="${input_base}/$OPTARG"
      fi
      ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) storage="$OPTARG" ;;
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
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing required -f argument."
  brief_help
  exit 1
fi

if [[ ! -f "$input_list" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Accession list not found: $input_list"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script"
  exit 1
fi

mkdir -p "$log_dir"
log_date=$(date +%Y%m%d)

# --- Efficiency Check --- Not needed for this script but left for consistency
num_tasks=$(wc -l < "$input_list")
effective_ncpus=$(( num_tasks * ncpus_per_task ))

if (( effective_ncpus < ncpus )); then
  echo -e "\033[1;33m⚠️ WARNING:\033[0m You requested $ncpus CPUs but only ${effective_ncpus} would be used efficiently for $num_tasks tasks."
  echo -e "\033[1;33m⚠️ Consider reducing -c option to ${effective_ncpus} CPUs to optimize resource usage.\033[0m"
  echo ""
fi


# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting a single PBS job for full input list...\033[0m"
  chunk_jobname="${job_name}_single"

  qsub -N "$chunk_jobname" \
     -o "$log_dir/${chunk_jobname}_${log_date}_pbs.out" \
     -e "$log_dir/${chunk_jobname}_${log_date}_pbs.err" \
     -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
     -l storage="$storage" -q "$queue" -P "$root_project" \
     -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$USER",NCPUS_PER_TASK="$ncpus_per_task" \
     "${script_dir}/${project}_parallel_task_launcher.pbs"

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
         -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$USER",NCPUS_PER_TASK="$ncpus_per_task" \
         "${script_dir}/${project}_parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m Launched $num_jobs PBS jobs from chunks under: $chunk_dir\033[0m"
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

