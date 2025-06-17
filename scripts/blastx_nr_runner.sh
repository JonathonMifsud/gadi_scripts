#!/bin/bash

############################################################################################################
# Script Name: blastnr_runner.sh
# Description: Submits a single DIAMOND blastx job for deduplicated RdRp+RVDB contigs from accession list.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# NEED TO ADD THE NEWER PARALLEL OPTIONS (-k and -n) 

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project="mytest"                
root_project="fo27"               
user=$(whoami)

# ----------------------------------------
# Job Configuration
# ----------------------------------------

job_name="blastnr"
ncpus=12
mem="120GB"
walltime="48:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
script_dir="${base_dir}/scripts"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
blast_results_dir="${base_dir}/blast_results"
task_script="${script_dir}/blastx_nr_worker.sh"

# DIAMOND Database
nr_db=""

# ----------------------------------------
# Help Function
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]"
  echo -e "For full help: $0 -h"
}

show_help() {
  echo -e ""
  echo -e "\033[1;34mUsage:\033[0m"
  echo "  $0 -f accession_list.txt [options]"
  echo ""
  echo "This script submits a DIAMOND blastx job using all RdRp and RVDB contigs"
  echo "for the accessions listed in the provided file."
  echo ""

  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f   Accession list file (must exist in ${input_base} or full path)"

  echo -e "\n\033[1;34mOptions:\033[0m"
  echo "  -d   DIAMOND database [example: /g/data/fo27/databases/blast/nr.Jun-2025.dmnd]"
  echo "  -p   NCI project code [default: ${root_project}]"
  echo "  -q   PBS queue [default: ${queue}]"
  echo "  -c   Number of CPUs [default: ${ncpus}]"
  echo "  -m   Total memory (e.g., 120GB) [default: ${mem}]"
  echo "  -t   Walltime [default: ${walltime}]"
  echo "  -h   Show this help message"

  echo -e "\n\033[1;34mExample:\033[0m"
  echo "  $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone.txt -d /g/data/fo27/databases/blast/nr.Jun-2025.dmnd -c 12 -m 120GB"
  echo ""
  exit 1
}

# ----------------------------------------
# Parse Arguments
# ----------------------------------------

while getopts "f:d:p:q:c:m:t:h" opt; do
  case $opt in
    f)
      [[ "$OPTARG" = /* ]] && input_file="$OPTARG" || input_file="${input_base}/$OPTARG"
      ;;
    d) nr_db="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ -z "${input_file:-}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing -f argument."
  brief_help
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Accession list not found: $input_file"
  exit 1
fi

if [[ -z "${nr_db}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing -d DIAMOND NR database file."
  echo -e "\033[1;31m Look for the NR database in the following locations:\033[0m"
  echo -e "\033[1;31m 🥶 Frozen DBs /g/data/fo27/databases/blast/\033[0m"
  echo -e "\033[1;31m 😎 Fresh DBs /scratch/fo27/monthly_dbs/\033[0m"
  exit 1
fi

if [[ ! -f "${nr_db}" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Missing -d DIAMOND NR database file."
  echo -e "\033[1;31m Look for the NR database in the following locations:\033[0m"
  echo -e "\033[1;31m 🥶 Frozen DBs /g/data/fo27/databases/blast/\033[0m"
  echo -e "\033[1;31m 😎 Fresh DBs /scratch/fo27/monthly_dbs/\033[0m"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Worker script not executable: $task_script"
  exit 1
fi

# ----------------------------------------
# Contig File Existence and Size Check
# ----------------------------------------

echo -e "\033[34m🔍 Checking expected blast contig files...\033[0m"
contig_dir="${base_dir}/blast_results"
missing_files=()

while IFS= read -r id; do
  rdrp_file="${contig_dir}/${id}_rdrp_blastcontigs.fasta"
  rvdb_file="${contig_dir}/${id}_rvdb_blastcontigs.fasta"

  if [[ ! -s "$rdrp_file" ]]; then
    missing_files+=("❌ Missing or empty: $rdrp_file")
  fi
  if [[ ! -s "$rvdb_file" ]]; then
    missing_files+=("❌ Missing or empty: $rvdb_file")
  fi
done < "$input_file"

if (( ${#missing_files[@]} > 0 )); then
  echo -e "\033[1;31m⚠️  WARNING: Some expected contig files are missing or empty:\033[0m"
  printf '%s\n' "${missing_files[@]}"
  echo ""

  read -p "Do you want to continue with job submission anyway? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n🛑 Stopping submission."
    exit 1
  fi
else
  echo -e "✅ All expected contig files exist and are non-empty."
fi

mkdir -p "$log_dir" "$blast_results_dir"
log_date=$(date +%Y%m%d)
accession_name=$(basename "$input_file" .txt)

# --- Update Diamond Parameters ---
diamond_params="--more-sensitive -e 1e-4 -b4 -p ${ncpus} -k10"

# ----------------------------------------
# Submit PBS Job
# ----------------------------------------

echo -e "\033[34mSubmitting blastnr job for accession set: $accession_name\033[0m"

qsub -N "${job_name}_${accession_name}" \
     -o "${log_dir}/${job_name}_${accession_name}_${log_date}_pbs.out" \
     -e "${log_dir}/${job_name}_${accession_name}_${log_date}_pbs.err" \
     -l ncpus="${ncpus}" -l mem="${mem}" -l walltime="${walltime}" \
     -l storage="${storage}" -q "${queue}" -P "${root_project}" \
     -v input_list="$input_file",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus",NR_DB="$nr_db",DIAMOND_PARAMS="$diamond_params" \
     "${task_script}"

echo -e "\033[32m✅ Job submitted for: $input_file\033[0m"
# --- Parse and summarize walltime ---
IFS=: read -r hh mm ss <<< "$walltime"
total_walltime_secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))

# --- Final Summary ---
echo -e "\nPBS Job Configuration Summary:"
printf "   Job name:                %s\n" "${job_name}_${accession_name}"
printf "   CPUs allocated:          %s\n" "$ncpus"
printf "   Memory allocated:        %s\n" "$mem"
printf "   Walltime allocated:      %s (%s seconds)\n" "$walltime" "$total_walltime_secs"
echo "   Note: This job is not parallelized. All resources are used by a single task."

