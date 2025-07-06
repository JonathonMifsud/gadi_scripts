#!/bin/bash

############################################################################################################
# Script Name: bbmap_runner.sh
# Description: Launches one or more BBMap mapping array jobs using PBS on Gadi from a CSV list.
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

job_name="bbmap"
ncpus=6
mem="60GB"
walltime="04:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"
num_jobs=1

# ----------------------------------------
# Paths (computed later)
# ----------------------------------------

csv_file=""
script_dir=""
log_dir=""
worker_script=""

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -p <project> -f /path/to/mapping.csv [options]"
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo -e "  $0 -p <project> -f /full/path/to/mapping.csv [options]\n"
  echo "This script launches one or more BBMap mapping jobs on Gadi from a CSV file with:"
  echo "  1. library_id:             Name of the trimmed FASTQ prefix (can be semicolon-separated)"
  echo "  2. reference_fasta:        Name of the FASTA file in mapping/reference/"
  echo "  3. min_identity:           Minimum identity for BBMap alignment (e.g. 0.99)"
  echo -e "\n\033[1;34mExample Input CSV:\033[0m"
  echo "rspcaperth5,canine_calicivirus_strain_rspcaperth5a.fasta,0.99"
  echo "HPV152RL2;HPV152RL3,norovirus_GVI_dog_HPV152RL3.fasta,0.99"
  echo "rspcacw5,canine_astrovirus_strain_rspcacw5_capsid.fasta,0.99"
  echo "" 
  echo -e "\nSemicolons (;) can be used to specify multiple input libraries to map together in a single run."
  echo -e "This is different from mapping two libraries separately to the same reference, as the output will be a single BAM file.\n"
  echo -e "\n\033[1;34mRequired:\033[0m"
  echo "  -p    Project name (under /scratch/<root>/<user>/)"
  echo "  -f    Full path to mapping CSV file"

  echo -e "\n\033[1;34mOptions:\033[0m"
  echo "  -j    PBS job name [default: ${job_name}]"
  echo "  -c    Number of CPUs per job [default: ${ncpus}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    Queue name [default: ${queue}]"
  echo "  -r    NCI root project code [default: ${root_project}]"
  echo "  -s    Storage flag for PBS [default: ${storage}]"
  echo "  -n    Number of PBS jobs to split the CSV into [default: ${num_jobs}]"
  echo "  -h    Show this help message"

  echo -e "\n\033[1;34mGitHub:\033[0m"
  echo "  https://github.com/JonathonMifsud/gadi_scripts"
  echo ""
  exit 1
}

# ----------------------------------------
# Parse Command Line Arguments
# ----------------------------------------

while getopts "p:f:j:c:m:t:q:r:s:n:h" opt; do
  case "$opt" in
    p) project="$OPTARG" ;;
    f) csv_file="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    r) root_project="$OPTARG" ;;
    s) storage="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validate Inputs
# ----------------------------------------

if [[ -z "$project" || -z "$csv_file" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Both -p and -f must be specified."
  brief_help
  exit 1
fi

if [[ ! -f "$csv_file" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Mapping CSV file not found: $csv_file"
  exit 1
fi

base_dir="/scratch/${root_project}/${user}/${project}"
script_dir="${base_dir}/scripts"
log_dir="${base_dir}/logs"
worker_script="${script_dir}/bbmap_worker.sh"

if [[ ! -x "$worker_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $worker_script"
  exit 1
fi

mkdir -p "$log_dir"

log_date=$(date +%Y%m%d)

# ----------------------------------------
# Submit PBS Jobs (single or chunked)
# ----------------------------------------

if (( num_jobs == 1 )); then
  echo -e "\033[34m📦 Submitting single PBS array job...\033[0m"
  num_lines=$(wc -l < "$csv_file")
  end_index=$((num_lines - 1))
  [[ "$end_index" == "0" ]] && end_index="1"

  qsub -J 0-${end_index} \
    -N "$job_name" \
    -o "${log_dir}/${job_name}_%J_%I.out" \
    -e "${log_dir}/${job_name}_%J_%I.err" \
    -l select=1:ncpus=$ncpus:mem=$mem \
    -l walltime=$walltime -l storage=$storage \
    -q "$queue" -P "$root_project" \
    -v PROJECT="$project",ROOT_PROJECT="$root_project",CSV_PATH="$csv_file",USER="$user" \
    "$worker_script"

  echo -e "\033[32m✅ Launched single array job for ${num_lines} lines\033[0m"

else
  echo -e "\033[34m🔀 Splitting input CSV into ${num_jobs} chunks...\033[0m"
  chunk_dir="${csv_file}_chunks_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$csv_file" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_lines=$(wc -l < "$chunk_file")
    end_index=$((chunk_lines - 1))
    [[ "$end_index" == "0" ]] && end_index="1"

    chunk_jobname="${job_name}_${chunk_name}"

    qsub -J 0-${end_index} \
      -N "$chunk_jobname" \
      -o "${log_dir}/${chunk_jobname}_%J_%I.out" \
      -e "${log_dir}/${chunk_jobname}_%J_%I.err" \
      -l select=1:ncpus=$ncpus:mem=$mem \
      -l walltime=$walltime -l storage=$storage \
      -q "$queue" -P "$root_project" \
      -v PROJECT="$project",ROOT_PROJECT="$root_project",CSV_PATH="$chunk_file",USER="$user" \
      "$worker_script"

    echo -e "\033[32m✅ Launched job: $chunk_jobname for ${chunk_lines} lines\033[0m"
  done

  echo -e "\033[34m📁 All chunks submitted from: $chunk_dir\033[0m"
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

