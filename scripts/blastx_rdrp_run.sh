#!/bin/bash

############################################################################################################
# Script Name: blastx_rdrp_run.sh
# Author: JCO Mifsud jonathon.mifsud1@gmail.com
# Description: Launches DIAMOND blastx jobs against the RdRp database using nci-parallel and PBS on Gadi.
# Please remember to cite Justine's database paper! https://academic.oup.com/ve/article-abstract/8/2/veac082/6679729
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project="mytest"                 # Project name for organizational purposes (under /scratch)
root_project="fo27"              # Gadi NCI project code (PBS -P flag)
user=$(whoami)                   # User ID (Automatically pulled from system)

# ----------------------------------------
# Job Configuration (PBS settings)
# ----------------------------------------

job_name="blastx_rdrp"           # Base name for PBS jobs
ncpus=12                         # Total CPUs requested for a PBS job
ncpus_per_task=6                 # CPUs per individual task
mem="30GB"                       # Memory per PBS job
walltime="04:00:00"              # Max walltime
num_jobs=1                       # Number of PBS jobs to split input into
queue="normal"                   # PBS queue
storage="gdata/${root_project}+scratch/${root_project}" # PBS storage

# ----------------------------------------
# Paths
# ----------------------------------------

script_dir="/scratch/${root_project}/${user}/${project}/scripts"
input_base="/scratch/${root_project}/${user}/${project}/accession_lists"
log_dir="/scratch/${root_project}/${user}/${project}/logs"
task_script="${script_dir}/blastx_rdrp_worker.sh"

# Default RdRp DB (can be overridden)
rdrp_db="/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.dmnd"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone.txt [options]"
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -f accession_list.txt [options]"
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
  echo -e "  $0 -f setone -n 4"
  echo -e ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:j:c:k:m:t:q:p:r:n:d:h" opt; do
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

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting a single PBS job for full input list...\033[0m"
  chunk_jobname="${job_name}_single"

  qsub -N "$chunk_jobname" \
    -o "$log_dir/${chunk_jobname}_${log_date}_pbs.out" \
    -e "$log_dir/${chunk_jobname}_${log_date}_pbs.err" \
    -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
    -q "$queue" -P "$root_project" \
    -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RDRP_DB="$rdrp_db" \
    "${script_dir}/parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched single PBS job: $input_list\033[0m"

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
      -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
      -q "$queue" -P "$root_project" \
      -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RDRP_DB="$rdrp_db" \
      "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ All chunked jobs launched under: $chunk_dir\033[0m"
fi
