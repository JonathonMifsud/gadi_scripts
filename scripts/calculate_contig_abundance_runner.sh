#!/bin/bash

############################################################################################################
# Script Name: calculate_contig_abundance_runner.sh
# Description: Launches a parallel RSEM abundance estimation job using nci-parallel and PBS on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# ----------------------------------------------------------------------------------
# NOTE: Why we don't use Singularity for RSEM 
# ----------------------------------------------------------------------------------
# Although there is a container available for both Trinity and RSEM that can be used
# We are a little weird in that we use the support script align_and_estimate_abundance.pl
# to run Trinity with RSEM and Bowtie2.
# Neither Trinity nor RSEM have everything we need in their containers to run this
# and binding the binaries from one image to the path of the other
# leads to a bunch of issues with the perl library.
#
# As Gadi has Trinity and Bowtie2 modules
# and we have installed RSEM into a shared directory /g/data/fo27/software/other_software/rsem
# we can use these directly without the need for a container.
# ----------------------------------------------------------------------------------

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

job_name="abundance_reads"
ncpus=12
ncpus_per_task=6
mem="30GB"
walltime="04:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
script_dir="${base_dir}/scripts"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
task_script="${script_dir}/${project}_calculate_contig_abundance_worker.sh"
abundance_dir="${base_dir}/abundance"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone [options]"
  echo ""
  echo "For full help, use: $0 -h"
}

show_help() {
  echo ""
  echo -e "\033[1;34mUsage:\033[0m"
  echo "  $0 -f accession_list.txt [options]"
  echo ""
  echo "This script launches a parallel RSEM abundance estimation job using nci-parallel and PBS on Gadi."
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Name of accession list file (must exist in ${input_base})"
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -j    Job name [default: ${job_name}]"
  echo "  -c    Number of CPUs [default: ${ncpus}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -k    Number of CPUs per task [default: ${ncpus_per_task}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    PBS queue [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Storage resources [default: ${storage}]"
  echo "  -n    Number of PBS jobs [default: ${num_jobs}]"
  echo "  -h    Show this help message"
  echo ""
  echo -e "\033[1;34mExample:\033[0m"
  echo "  $0 -f setone"
  echo "  $0 -f setone -n 4 -c 24 -k 6"
  echo ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:j:c:m:t:q:p:r:n:k:h" opt; do
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

mkdir -p "$log_dir" "${abundance_dir}/final_abundance"
log_date=$(date +%Y%m%d)

# --- Efficiency Check ---
num_tasks=$(wc -l < "$input_list")
effective_ncpus=$(( num_tasks * ncpus_per_task ))

if (( effective_ncpus < ncpus )); then
  echo -e "\033[1;33m⚠️ WARNING:\033[0m You requested $ncpus CPUs, but only $effective_ncpus would be used efficiently for $num_tasks tasks."
  echo -e "\033[1;33m⚠️ Tip:\033[0m Consider lowering -c to $effective_ncpus or adjusting -k (CPUs per task) to better match."
  echo ""
fi

# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting a single PBS job for full input list...\033[0m"
  chunk_jobname="${job_name}_single"

  qsub -N "$chunk_jobname" \
     -o "${log_dir}/${chunk_jobname}_${log_date}_pbs.out" \
     -e "${log_dir}/${chunk_jobname}_${log_date}_pbs.err" \
     -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
     -l storage="$storage" -q "$queue" -P "$root_project" \
     -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$USER",NCPUS_PER_TASK="$ncpus_per_task" \
     "${script_dir}/${project}_parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched single PBS job for accession list: $input_list\033[0m"

else
  echo -e "\033[34m Splitting input list into $num_jobs chunks...\033[0m"
  chunk_dir="${input_base}/chunks_$(basename "$input_list")_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"

  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_jobname="${job_name}_${chunk_name}"

    qsub -N "$chunk_jobname" \
         -o "${log_dir}/${chunk_jobname}_${log_date}_pbs.out" \
         -e "${log_dir}/${chunk_jobname}_${log_date}_pbs.err" \
         -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
         -l storage="$storage" -q "$queue" -P "$root_project" \
         -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$USER",NCPUS_PER_TASK="$ncpus_per_task" \
         "${script_dir}/${project}_parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ Launched $num_jobs PBS jobs from chunks under: $chunk_dir\033[0m"
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
