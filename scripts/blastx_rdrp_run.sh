#!/bin/bash

############################################################################################################
# Script Name: blastx_rdrp_run.sh
# Author: JCO Mifsud jonathon.mifsud1@gmail.com
# Description: Launches DIAMOND blastx jobs against the RdRp database
# Please remember to cite Justine's database paper! https://academic.oup.com/ve/article-abstract/8/2/veac082/6679729
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Default Configuration
# ----------------------------------------
project="mytest"
root_project="fo27"
user=$(whoami)

job_name="blastx_rdrp"
ncpus=12
ncpus_per_task=6
mem="30GB"
walltime="06:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# Default RdRp DB path (can be overridden with -d option)
rdrp_db="/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.dmnd"

# ----------------------------------------
# Directory Setup
# ----------------------------------------
base_dir="/scratch/${root_project}/${user}/${project}"
input_base="${base_dir}/contigs/final_contigs"
script_dir="${base_dir}/scripts"
log_dir="${base_dir}/logs"
task_script="${script_dir}/blastx_rdrp_worker.sh"
output_dir="${base_dir}/blast_results"

mkdir -p "$log_dir" "$output_dir"

# ----------------------------------------
# Help Functions
# ----------------------------------------
brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f accession_list.txt [options]"
  echo -e "\nFor full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -f accession_list.txt [options]"
  echo -e ""
  echo "This script launches DIAMOND blastx jobs against the RdRp database"
  echo -e "\n\033[1;34mRequired:\033[0m"
  echo "  -f    Path to input list of contig FASTA files (one per line)."
  echo -e "\n\033[1;34mOptions:\033[0m"
  echo "  -d    Path to RdRp DIAMOND database [default: ${rdrp_db}]"
  echo "  -j    Job name [default: ${job_name}]"
  echo "  -c    Number of CPUs per PBS job [default: ${ncpus}]"
  echo "  -m    Memory per PBS job [default: ${mem}]"
  echo "  -k    Number of CPUs per task [default: ${ncpus_per_task}]"
  echo "  -t    Walltime [default: ${walltime}]"
  echo "  -q    PBS queue [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Storage resources [default: ${storage}]"
  echo "  -n    Number of parallel PBS jobs [default: ${num_jobs}]"
  echo "  -h    Show help message"
  echo -e ""
  echo -e "\033[1;34mExample:\033[0m"
  echo -e "  $0 -f list.txt -d /path/to/custom.dmnd -n 4"
  echo -e ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------
while getopts "f:j:c:m:k:t:q:p:r:n:d:h" opt; do
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
    k) ncpus_per_task="$OPTARG" ;;
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

if [[ -z "${input_list:-}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing required -f argument."
  brief_help
  exit 1
fi

if [[ ! -f "$input_list" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Input list not found: $input_list"
  exit 1
fi

if [[ ! -f "$rdrp_db" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m RdRp database not found: $rdrp_db"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script"
  exit 1
fi

log_date=$(date +%Y%m%d)

# --- Efficiency Check ---
num_tasks=$(wc -l < "$input_list")
effective_ncpus=$(( num_tasks * ncpus_per_task ))
if (( effective_ncpus < ncpus )); then
  echo -e "\033[1;33m⚠️ WARNING:\033[0m You requested $ncpus CPUs but only $effective_ncpus are used across $num_tasks tasks."
  echo -e "\033[1;33m⚠️ Consider reducing -c to $effective_ncpus or increasing -k to use more per task.\033[0m"
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
  echo -e "\033[34m Splitting input into $num_jobs chunks...\033[0m"
  chunk_dir="${input_base}/chunks_${job_name}_${log_date}"
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

  echo -e "\033[32m✅ Launched $num_jobs PBS jobs from: $chunk_dir\033[0m"
fi
