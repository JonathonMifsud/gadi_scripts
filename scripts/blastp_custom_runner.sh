#!/bin/bash

############################################################################################################
# Script Name: blastp_custom_runner.sh
# Description: Submits one or more DIAMOND blastp jobs for user-specified protein inputs and database on Gadi.
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
# Default Configuration
# ----------------------------------------

job_name="blastp_custom"
ncpus=12
mem="64GB"
walltime="48:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"
num_jobs=1
diamond_params="--more-sensitive -e 1e-4 -k 10"

# Paths
script_dir="/scratch/${root_project}/${user}/${project}/scripts"
log_dir="/scratch/${root_project}/${user}/${project}/logs"
task_script="${script_dir}/blastp_custom_worker.sh"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\nUsage: $0 -i input.fa OR -l list.txt -d db.dmnd [options]"
  echo -e "Use -h for full documentation.\n"
}

show_help() {
  cat <<EOF

Usage:
  $0 -i input_protein_fasta -d diamond_db.dmnd [options]
  $0 -l list_of_fastas.txt -d diamond_db.dmnd [options]

Description:
  Launches DIAMOND blastp jobs on Gadi. Supports both:
    - A single input file (-i)
    - A file listing multiple input FASTAs (-l)

  Results are saved to the specified output directory (-o) or alongside the input.
  Output files are annotated using the database name for traceability.

Required:
  -i        Input protein FASTA file (for single job) OR
  -l        Text file with paths to multiple FASTAs (for multiple jobs)
  -d        DIAMOND database (.dmnd format)

Optional:
  -o        Output directory [default: input directory]
  -j        Job name prefix [default: ${job_name}]
  -c        CPUs per job [default: ${ncpus}]
  -m        Memory per job [default: ${mem}]
  -t        Walltime [default: ${walltime}]
  -q        PBS queue [default: ${queue}]
  -p        NCI project code [default: ${root_project}]
  -s        PBS storage resources [default: ${storage}]
  -n        Number of parallel jobs (used with -l) [default: ${num_jobs}]
  -x        Custom DIAMOND parameters in quotes
            [default: '${diamond_params}']
  -h        Show this help message

Examples:
  Run a single job:
    $0 -i /scratch/fo27/user/my_proteins.fa -d /g/data/fo27/dbs/uniprot.dmnd

  Run multiple jobs in parallel:
    $0 -l inputs.txt -d /g/data/fo27/dbs/uniprot.dmnd -o /scratch/fo27/user/results -n 4

  Override DIAMOND parameters:
    $0 -i proteins.fa -d db.dmnd -x "--ultra-sensitive -e 1e-5 -k 5"

Notes:
  - DIAMOND parameters control sensitivity, e-value, hits per query, etc.
  - Default is '${diamond_params}'.
  - The input list (-l) must contain one full file path per line.

GitHub:
  https://github.com/JonathonMifsud/gadi_scripts

EOF
  exit 0
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

input=""
list=""
db=""
outdir=""
while getopts "i:l:d:o:j:c:m:t:q:p:s:n:x:h" opt; do
  case $opt in
    i) input="$OPTARG" ;;
    l) list="$OPTARG" ;;
    d) db="$OPTARG" ;;
    o) outdir="$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) root_project="$OPTARG" ;;
    s) storage="$OPTARG" ;;
    n) num_jobs="$OPTARG" ;;
    x) diamond_params="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ -z "$input" && -z "$list" ]]; then
  echo -e "❌ ERROR: Must provide either -i (input fasta) or -l (list of inputs)"
  brief_help; exit 1
fi

if [[ -n "$input" && ! -f "$input" ]]; then
  echo -e "❌ ERROR: Input file not found: $input"
  exit 1
fi

if [[ -n "$list" && ! -f "$list" ]]; then
  echo -e "❌ ERROR: Input list file not found: $list"
  exit 1
fi

if [[ -z "$db" || ! -f "$db" ]]; then
  echo -e "❌ ERROR: DIAMOND database (-d) is required and must exist"
  exit 1
fi

mkdir -p "$log_dir"

# ----------------------------------------
# Job Submission Function
# ----------------------------------------

submit_job() {
  local fasta="$1"
  local base=$(basename "$fasta" .fa)
  local db_tag=$(basename "$db" .dmnd)
  local log_date=$(date +%Y%m%d)
  local output_dir="${outdir:-$(dirname "$fasta")}"

  mkdir -p "$output_dir"

  qsub -N "${job_name}_${base}" \
    -o "${log_dir}/${base}_${log_date}_pbs.out" \
    -e "${log_dir}/${base}_${log_date}_pbs.err" \
    -l ncpus="${ncpus}" -l mem="${mem}" -l walltime="${walltime}" \
    -l storage="${storage}" -q "${queue}" -P "${root_project}" \
    -v input="$fasta",db="$db",outdir="$output_dir",NCPUS="$ncpus",DB_TAG="$db_tag",DIAMOND_PARAMS="$diamond_params" \
    "$task_script"

  echo -e "✅ Submitted job: ${base} -> ${db_tag}"
}

# ----------------------------------------
# Parallel Job Distribution
# ----------------------------------------

if [[ -n "$input" ]]; then
  submit_job "$input"
else
  total_inputs=$(wc -l < "$list")
  if (( num_jobs > 1 && total_inputs > num_jobs )); then
    echo -e "\n📦 Splitting input list into $num_jobs chunks..."
    chunk_dir=$(mktemp -d)
    split -d -n l/$num_jobs "$list" "$chunk_dir/chunk_"

    for chunk in "$chunk_dir"/chunk_*; do
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        submit_job "$line"
      done < "$chunk"
    done
    rm -r "$chunk_dir"
  else
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      submit_job "$line"
    done < "$list"
  fi
fi

echo -e "\n🎉 All blastp jobs have been submitted."

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

