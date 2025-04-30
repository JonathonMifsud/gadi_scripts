#!/bin/bash

############################################################################################################
# Script Name: calculate_contig_abundance_run.sh
# Author: JCO Mifsud jonathon.mifsud1@gmail.com
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

project="mytest"
root_project="fo27"
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
task_script="${script_dir}/calculate_contig_abundance_worker.sh"
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
     "${script_dir}/parallel_task_launcher.pbs"

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
         "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ Launched $num_jobs PBS jobs from chunks under: $chunk_dir\033[0m"
fi
