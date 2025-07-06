#!/bin/bash

############################################################################################################
# Script Name: blastx_rvdb_runner.sh
# Description: Launches DIAMOND blastx jobs against the RVDB protein database using PBS on Gadi.
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

job_name="blastx_rvdb"
ncpus=18
ncpus_per_task=6
mem="120GB"
walltime="48:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

script_dir="/scratch/${root_project}/${user}/${project}/scripts"
base_dir="/scratch/${root_project}/${user}/${project}"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
task_script="${script_dir}/blastx_rvdb_worker.sh"
blast_dir="${base_dir}/blast_results"

# No default DB — user must provide
rvdb_db=""

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone.txt -d /g/data/fo27/databases/blast/rvdb/rvdb_prot_v29_may-2025/rvdb_prot_v29_rvdb_prot_v29_may-2025.fasta.dmnd [options]"
  echo -e "\nFor full help, use: \033[1m$0 -h\033[0m"
  echo ""
  echo A clustered and non_clustered verison of the RVDB protein database exist in /g/data/fo27/databases/blast/
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo -e "  $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt -d /g/data/fo27/databases/blast/rvdb/rvdb_prot_v29_may-2025/rvdb.dmnd [options]"
  echo ""
  echo "This script launches DIAMOND blastx jobs against the RVDB protein database using PBS on Gadi."
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Accession list file (one ID per line)"
  echo "  -d    Full path to RVDB DIAMOND database (e.g. /g/data/fo27/databases/blast/rvdb/rvdb_prot_v3_may_2025/rvdb_prot_v3_may_2025.dmnd)"
  echo ""
  echo A clustered and non_clustered verison of the RVDB protein database exist in /g/data/fo27/databases/blast/
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
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
  echo ""
  echo -e "\033[1;34mExample:\033[0m"
  echo "  $0 -f setone -d /g/data/fo27/databases/blast/rvdb/rvdb_prot_v3_may_2025/rvdb_prot_v3_may_2025.dmnd -n 4"
  echo ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

while getopts "f:d:j:c:m:t:q:p:r:n:k:h" opt; do
  case $opt in
    f)
      [[ "$OPTARG" = /* ]] && input_list="$OPTARG" || input_list="${input_base}/$OPTARG"
      ;;
    d) rvdb_db="$OPTARG" ;;
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

if [[ $# -eq 0 || -z "${input_list:-}" || -z "$rvdb_db" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing required arguments."
  brief_help
  exit 1
fi

[[ ! -f "$input_list" ]] && echo -e "\033[1;31m❌ ERROR:\033[0m Accession list not found: $input_list" && exit 1
[[ ! -f "$rvdb_db" ]] && echo -e "\033[1;31m❌ ERROR:\033[0m RVDB database not found: $rvdb_db" && exit 1
[[ ! -x "$task_script" ]] && echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script" && exit 1

mkdir -p "$log_dir" "$blast_dir"
log_date=$(date +%Y%m%d)

num_tasks=$(wc -l < "$input_list")
effective_ncpus=$(( num_tasks * ncpus_per_task ))

if (( effective_ncpus < ncpus )); then
  echo -e "\033[1;33m⚠️ WARNING:\033[0m Requested $ncpus CPUs, but only $effective_ncpus will be used."
  echo -e "\033[1;33m⚠️ Consider reducing -c or increasing -k.\033[0m"
  echo ""
fi

# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

if (( num_jobs == 1 )); then
  chunk_jobname="${job_name}_single"

  qsub -N "$chunk_jobname" \
       -o "$log_dir/${chunk_jobname}_${log_date}.out" \
       -e "$log_dir/${chunk_jobname}_${log_date}.err" \
       -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
       -q "$queue" -P "$root_project" \
       -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RVDB_DB="$rvdb_db" \
       "${script_dir}/parallel_task_launcher.pbs"

  echo -e "\033[32m✅ Launched PBS job: $chunk_jobname\033[0m"
else
  chunk_dir="${input_base}/chunks_$(basename "$input_list")_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    chunk_jobname="${job_name}_${chunk_name}"

    qsub -N "$chunk_jobname" \
         -o "$log_dir/${chunk_jobname}_${log_date}.out" \
         -e "$log_dir/${chunk_jobname}_${log_date}.err" \
         -l ncpus="$ncpus",mem="$mem",walltime="$walltime",storage="$storage" \
         -q "$queue" -P "$root_project" \
         -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus_per_task",RVDB_DB="$rvdb_db" \
         "${script_dir}/parallel_task_launcher.pbs"

    echo -e "\033[32m✅ Launched PBS job: $chunk_jobname for chunk: $chunk_file\033[0m"
  done

  echo -e "\033[32m✅ All PBS jobs launched from: $chunk_dir\033[0m"
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

