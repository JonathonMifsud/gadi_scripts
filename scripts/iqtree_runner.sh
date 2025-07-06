#!/bin/bash

############################################################################################################
# Script Name: iqtree_runner.sh
# Description: Submits PBS jobs to run IQ-TREE on alignment files with consistent logging and model extraction.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

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

job_name="iqtree"
ncpus=8
mem="16GB"
walltime="04:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"
model="MFP"
extra_args=""

# ----------------------------------------
# Paths
# ----------------------------------------

base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
script_dir="${base_dir}/scripts"
task_script="${script_dir}/${project}_iqtree_worker.sh"

mkdir -p "${log_dir}"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -i alignment.fasta OR -f file_list.txt [options]"
  echo -e "For full help, use: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -i alignment.fasta [options]"
  echo "  $0 -f alignment_list.txt [options]"
  echo ""
  echo "This script submits PBS jobs to run IQ-TREE on one or more alignment files."
  echo ""
  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -i    Single alignment file (FASTA/PHYLIP)"
  echo "  -f    File containing list of alignments (one per line)"
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -m    Substitution model (default: MFP)"
  echo "  -c    CPUs per job (default: ${ncpus})"
  echo "  -t    Walltime (default: ${walltime})"
  echo "  -q    PBS queue (default: ${queue})"
  echo "  -p    NCI project code (default: ${root_project})"
  echo "  -r    Root project directory (default: ${root_project})"
  echo "  -a    Additional IQ-TREE arguments (quoted string)"
  echo "  -h    Show this help message"
  echo ""
  echo -e "\033[1;34mExample:\033[0m"
  echo "  $0 -i myalignment.fasta -m GTR+G -c 6"
  echo "  $0 -f mylist.txt -a \"-mset LG,WAG,JTT\""
  echo ""
  echo -e "\033[1;34mGitHub:\033[0m"
  echo "  https://github.com/JonathonMifsud/gadi_scripts"
  echo ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

input_file=""
input_list=""

while getopts "i:f:m:c:t:q:p:r:a:h" opt; do
  case $opt in
    i) input_file="$OPTARG" ;;
    f) input_list="$OPTARG" ;;
    m) model="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    r) root_project="$OPTARG" ;;
    a) extra_args="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ -z "$input_file" && -z "$input_list" ]]; then
  echo -e "\033[1;31mERROR:\033[0m Must provide either -i (single file) or -f (file list)."
  brief_help
  exit 1
fi

if [[ -n "$input_file" && -n "$input_list" ]]; then
  echo -e "\033[1;31mERROR:\033[0m Cannot use both -i and -f at the same time."
  brief_help
  exit 1
fi

if [[ -n "$input_file" && ! -f "$input_file" ]]; then
  echo -e "\033[1;31mERROR:\033[0m Input file not found: $input_file"
  exit 1
fi

if [[ -n "$input_list" && ! -f "$input_list" ]]; then
  echo -e "\033[1;31mERROR:\033[0m Alignment list file not found: $input_list"
  exit 1
fi

if [[ ! -x "$task_script" ]]; then
  echo -e "\033[1;31mERROR:\033[0m Worker script not executable: $task_script"
  exit 1
fi

log_date=$(date +%Y%m%d)

# ----------------------------------------
# Build list of alignments
# ----------------------------------------

alignments=()

if [[ -n "$input_file" ]]; then
  alignments+=("$input_file")
else
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    alignments+=("$line")
  done < "$input_list"
fi

# ----------------------------------------
# Submit PBS Jobs
# ----------------------------------------

for aln in "${alignments[@]}"; do
  if [[ ! -f "$aln" ]]; then
    echo -e "\033[1;31mERROR:\033[0m File does not exist: $aln"
    continue
  fi

  aln_base=$(basename "$aln")
  aln_id="${aln_base%.*}"
  aln_id_sanitized=$(echo "$aln_id" | sed 's/[^A-Za-z0-9._-]/_/g')
  jobtag="${job_name}_${aln_id_sanitized}_${log_date}"
  job_config="${log_dir}/${jobtag}.jobvars"

  cat > "$job_config" <<EOF
alignment="$aln"
model="$model"
IQTREE_EXTRA_ARGS="$extra_args"
USER_ID="$user"
PROJECT_NAME="$project"
ROOT_PROJECT="$root_project"
EOF

  qsub -N "$jobtag" \
    -o "${log_dir}/${jobtag}.out" \
    -e "${log_dir}/${jobtag}.err" \
    -l ncpus="$ncpus" \
    -l mem="$mem" \
    -l walltime="$walltime" \
    -l storage="$storage" \
    -q "$queue" -P "$root_project" \
    -v JOB_CONFIG="$job_config" \
    "$task_script"

  echo "✅ Submitted: $aln"
done

# --- Parse and summarize walltime ---
IFS=: read -r hh mm ss <<< "$walltime"
total_walltime_secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))

# --- Final Summary ---
echo -e "\nPBS Job Configuration Summary:"
printf "   Job name:                %s\n" "${job_name}"
printf "   CPUs allocated:          %s\n" "$ncpus"
printf "   Memory allocated:        %s\n" "$mem"
printf "   Walltime allocated:      %s (%s seconds)\n" "$walltime" "$total_walltime_secs"
echo "   Note: This job is not parallelized. All resources are used by a single task."
