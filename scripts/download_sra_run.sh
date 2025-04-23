#!/bin/bash
# download_sra_run.sh
# Submits an nci-parallel job to download SRA libraries

set -e

# Default values
job_name="sra_download"
ncpus=6
mem="12GB"
walltime="04:00:00"
queue="normal"
project="fo27"
storage="gdata/fo27+scratch/fo27"
base_dir="$(cd "$(dirname "$0")/.." && pwd)"

show_help() {
  echo "Usage: $0 -f accessions.txt -s script.sh [-j jobname] [-c ncpus] [-m mem] [-t time] [-q queue] [-p project] [-r storage]"
  echo ""
  echo "Options:"
  echo "  -f    Path to accession list"
  echo "  -s    Path to worker script (e.g. bin/download_sra_worker.sh)"
  echo "  -j    Job name [default: sra_download]"
  echo "  -c    Number of CPUs [default: 6]"
  echo "  -m    Memory [default: 12GB]"
  echo "  -t    Walltime [default: 04:00:00]"
  echo "  -q    Queue [default: normal]"
  echo "  -p    NCI project [default: fo27]"
  echo "  -r    Storage resources [default: gdata/fo27+scratch/fo27]"
  exit 1
}

while getopts "f:s:j:c:m:t:q:p:r:h" opt; do
  case $opt in
    f) input_list=$(realpath "$OPTARG") ;;
    s) task_script=$(realpath "$OPTARG") ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) walltime="$OPTARG" ;;
    q) queue="$OPTARG" ;;
    p) project="$OPTARG" ;;
    r) storage="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

[[ -z "${input_list:-}" || -z "${task_script:-}" ]] && echo "❌ Missing required -f or -s argument." && show_help

qsub -N "$job_name" \
     -l ncpus="$ncpus" \
     -l mem="$mem" \
     -l walltime="$walltime" \
     -l storage="$storage" \
     -q "$queue" \
     -P "$project" \
     -v input_list="$input_list",task_script="$task_script" \
     "$base_dir/jobs/parallel_task_launcher.pbs"
