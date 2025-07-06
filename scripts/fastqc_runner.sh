#!/bin/bash
############################################################################################################
# Script Name: fastqc_run.sh
#   This script launches parallel FastQC jobs on Gadi using nci-parallel and PBS, based on an accession 
#   list of libraries provided with the -f flag. Users can choose which types of reads to analyze 
#   (raw, trimmed, unpaired) via the -t option, if you want more than one use commas.
#   The FastQC results for each library and read type are written to a shared project-level directory under `fastqc/`.
#
#   After all FastQC jobs finish, a MultiQC job is automatically submitted.
#   It aggregates the FastQC reports for only the libraries listed in -f and generates a 
#   summary HTML report
#    The report is saved under `multiqc/`
#
#   FastQC Output:   /scratch/<project>/<user>/<project_name>/fastqc/
#   MultiQC Output:  /scratch/<project>/<user>/<project_name>/multiqc/fastqc_summary.html

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
# Job Configuration
# ----------------------------------------

job_name="fastqc"
ncpus=4
ncpus_per_task=1
mem="16GB"
walltime="02:00:00"
num_jobs=1
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}+gdata/fo27+scratch/fo27" # Storage resource requirements for PBS job (gdata, scratch)

# ----------------------------------------
# Paths
# ----------------------------------------

script_dir="/scratch/${root_project}/${user}/${project}/scripts"
base_dir="/scratch/${root_project}/${user}/${project}"
input_base="${base_dir}/accession_lists"
log_dir="${base_dir}/logs"
task_script="${script_dir}/${project}_fastqc_worker.sh"
fastqc_out="${base_dir}/fastqc"
multiqc_out="${base_dir}/multiqc"
multiqc_script="${script_dir}/multiqc_runner.sh"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ----------------------------------------
# Help Functions
# ----------------------------------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]"
  echo -e "Try \033[1m$0 -h\033[0m for full help."
}

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -f accession_list.txt [options]"
  echo -e "\n\033[1;34mRequired:\033[0m"
  echo "  -f    Accession list file (under ${input_base}/ or full path)"
  echo -e "\n\033[1;34mOptions:\033[0m"
  echo "  -j    Job name [default: ${job_name}]"
  echo "  -c    Total CPUs [default: ${ncpus}]"
  echo "  -m    Memory per job [default: ${mem}]"
  echo "  -k    CPUs per task [default: ${ncpus_per_task}]"
  echo "  -t    Read types to run (raw|trimmed|unpaired) [default: all]"
  echo "  -n    Number of PBS jobs [default: ${num_jobs}]"
  echo "  -q    PBS queue [default: ${queue}]"
  echo "  -p    NCI project code [default: ${root_project}]"
  echo "  -r    Storage flags [default: gdata/${root_project}+scratch/${root_project}]"
  echo "  -h    Show this help message"
  echo -e "\n\033[1;34mMultiQC:\033[0m"
  echo "  Automatically runs MultiQC after all FastQC jobs finish."
  echo -e "  Output saved to: \033[1m${multiqc_out}\033[0m"
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

types="raw|trimmed|unpaired"

while getopts "f:j:c:m:t:q:p:r:n:k:h" opt; do
  case $opt in
    f) [[ "$OPTARG" = /* ]] && input_list="$OPTARG" || input_list="${input_base}/$OPTARG" ;;
    j) job_name="$OPTARG" ;;
    c) ncpus="$OPTARG" ;;
    m) mem="$OPTARG" ;;
    t) types="$OPTARG" ;;
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

mkdir -p "$log_dir" "$fastqc_out" "$multiqc_out"
log_date=$(date +%Y%m%d)

if [[ "$1" == "fastqc" && $# -lt 2 ]]; then
  echo "❌ ERROR: fastqc was called without input files. This may attempt to launch the GUI, which is not allowed on Gadi."
  exit 1
fi

# ----------------------------------------
# Job Submission
# ----------------------------------------

jobids=()

if (( num_jobs == 1 )); then
  echo -e "\033[34m Submitting single PBS job...\033[0m"
  jobid=$(qsub -N "${job_name}_single" \
       -o "${log_dir}/${job_name}_single_${log_date}_pbs.out" \
       -e "${log_dir}/${job_name}_single_${log_date}_pbs.err" \
       -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
       -l storage="$storage" -q "$queue" -P "$root_project" \
       -v input_list="$input_list",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",READ_TYPES="$types",NCPUS_PER_TASK="$ncpus_per_task" \
       "${script_dir}/${project}_parallel_task_launcher.pbs")
  jobids+=("${jobid}")
  echo -e "\033[32m✅ Launched job ID: $jobid\033[0m"
else
  chunk_dir="${input_base}/chunks_$(basename "$input_list")_${job_name}_${log_date}"
  mkdir -p "$chunk_dir"
  split -d -n l/$num_jobs "$input_list" "$chunk_dir/chunk_"

  for chunk_file in "$chunk_dir"/chunk_*; do
    chunk_name=$(basename "$chunk_file")
    jobid=$(qsub -N "${job_name}_${chunk_name}" \
         -o "${log_dir}/${job_name}_${chunk_name}_${log_date}_pbs.out" \
         -e "${log_dir}/${job_name}_${chunk_name}_${log_date}_pbs.err" \
         -l ncpus="$ncpus" -l mem="$mem" -l walltime="$walltime" \
         -l storage="$storage" -q "$queue" -P "$root_project" \
         -v input_list="$chunk_file",task_script="$task_script",ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",READ_TYPES="$types",NCPUS_PER_TASK="$ncpus_per_task" \
         "${script_dir}/${project}_parallel_task_launcher.pbs")
    jobids+=("${jobid}")
    echo -e "\033[32m✅ Launched job ID: $jobid for chunk: $chunk_file\033[0m"
  done
fi

# ----------------------------------------
# Submit MultiQC Job (dependent on FastQC)
# ----------------------------------------

depstring=$(IFS=: ; echo "${jobids[*]}")
qsub -W depend=afterok:$depstring \
     -N multiqc_summary \
     -o "${log_dir}/multiqc_summary_${log_date}.out" \
     -e "${log_dir}/multiqc_summary_${log_date}.err" \
     -l ncpus=1 -l mem=20GB -l walltime=04:00:00 \
     -l storage="$storage" -q "$queue" -P "$root_project" \
     -v PROJECT_NAME="$project",ROOT_PROJECT="$root_project",USER_ID="$user",INPUT_LIST="$(basename "$input_list")" \
     "$multiqc_script"

echo -e "\033[36m📊 MultiQC job submitted. Will run after all FastQC jobs complete.\033[0m"

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
