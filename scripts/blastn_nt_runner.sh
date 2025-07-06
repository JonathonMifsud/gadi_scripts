#!/bin/bash

############################################################################################################
# Script Name: blastnt_runner.sh
# Description: Submits a single BLASTN job for deduplicated RdRp+RVDB contigs from accession list.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

# NEED TO ADD THE NEWER PARALLEL OPTIONS (-k and -n) 

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Project Metadata
# ----------------------------------------

project=""
root_project=""
user=$(whoami)

# ----------------------------------------
# Job Configuration
# ----------------------------------------

job_name="blastnt"
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
task_script="${script_dir}/blastn_nt_worker.sh"

# BLAST parameters
nt_db=""
blast_params='-max_target_seqs 10 -evalue 1E-10 -subject_besthit'

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\nUsage: $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt -d /scratch/fo27/monthly_dbs/nt.Jun-2025/nt [options]"
  echo -e "Use -h for full documentation."
}

show_help() {
  cat <<EOF

Usage:
  $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt -d /scratch/fo27/monthly_dbs/nt.Jun-2025/nt [options]

Description:
  Submits a BLASTN job using all RdRp and RVDB contigs for the accessions listed.

Required:
  -f    Accession list file (one ID per line)
  -d    Path to NT database (no file extensions)

Options:
  -j    PBS job name prefix [default: ${job_name}]
  -c    Number of CPUs [default: ${ncpus}]
  -m    Memory (e.g. 120GB) [default: ${mem}]
  -t    Walltime (e.g. 48:00:00) [default: ${walltime}]
  -q    PBS queue [default: ${queue}]
  -p    NCI project code [default: ${root_project}]
  -r    PBS storage string [default: ${storage}]
  -h    Show this help message

Example:
  $0 -f setone.txt -d /scratch/fo27/monthly_dbs/nt.Jun-2025/nt -c 16 -m 128GB

EOF
  exit 0
}

# ----------------------------------------
# Parse Arguments
# ----------------------------------------

while getopts "f:d:j:c:m:t:q:p:r:h" opt; do
  case $opt in
    f) [[ "$OPTARG" = /* ]] && input_file="$OPTARG" || input_file="${input_base}/$OPTARG" ;;
    d) nt_db="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) storage="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ -z "${input_file:-}" ]]; then
  echo -e "❌ ERROR: Missing -f argument."
  brief_help
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo -e "❌ ERROR: Accession list not found: $input_file"
  exit 1
fi

if [[ -z "$nt_db" ]]; then
  echo -e "❌ ERROR: Missing -d NT database path."
  echo -e "Look in /g/data/fo27/databases/blast/ or /scratch/fo27/monthly_dbs/"
  exit 1
fi

if [[ ! -d "$(dirname "$nt_db")" ]]; then
  echo -e "❌ ERROR: Directory does not exist: $(dirname "$nt_db")"
  exit 1
fi

if ! ls "${nt_db}".n* >/dev/null 2>&1; then
  echo -e "❌ ERROR: Could not find any of: ${nt_db}.nsq / .nin / .nhr etc."
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "❌ ERROR: Worker script not executable: $task_script"
  exit 1
fi

# ----------------------------------------
# Contig File Check
# ----------------------------------------

echo -e "🔍 Checking expected blast contig files..."
contig_dir="${base_dir}/blast_results"
missing_files=()

while IFS= read -r id; do
  rdrp="${contig_dir}/${id}_rdrp_blastcontigs.fasta"
  rvdb="${contig_dir}/${id}_rvdb_blastcontigs.fasta"
  [[ ! -s "$rdrp" ]] && missing_files+=("❌ Missing or empty: $rdrp")
  [[ ! -s "$rvdb" ]] && missing_files+=("❌ Missing or empty: $rvdb")
done < "$input_file"

if (( ${#missing_files[@]} > 0 )); then
  echo -e "\n⚠️ WARNING: Some expected contig files are missing or empty:"
  printf '%s\n' "${missing_files[@]}"
  echo ""
  read -p "Do you want to continue with job submission anyway? [y/N]: " confirm
  [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Aborting." && exit 1
else
  echo "✅ All expected contig files exist and are non-empty."
fi

# ----------------------------------------
# Submit PBS Job
# ----------------------------------------

mkdir -p "$log_dir" "$blast_results_dir"
log_date=$(date +%Y%m%d)
accession_name=$(basename "$input_file" .txt)
uuid=$(uuidgen)

# Write params to a uniquely named file
mkdir -p "${base_dir}/tmp"
param_file="${base_dir}/tmp/blast_params_${accession_name}_${uuid}.txt"
echo "$blast_params" > "$param_file"

stdout_log="${log_dir}/${job_name}_${accession_name}_${log_date}_pbs.out"
stderr_log="${log_dir}/${job_name}_${accession_name}_${log_date}_pbs.err"

echo -e "\n📤 Submitting BLASTN job for: $accession_name"
echo -e "📄 Using parameter file: $param_file"

qsub -N "${job_name}_${accession_name}" \
     -o "$stdout_log" \
     -e "$stderr_log" \
     -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
     -l storage="$storage" -q "$queue" -P "$root_project" \
     -v input_list="$input_file",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",NCPUS_PER_TASK="$ncpus",NT_DB="$nt_db",PARAM_FILE="$param_file" \
     "$task_script"

echo -e "✅ Job submitted for: $input_file"
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

