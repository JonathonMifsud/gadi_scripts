#!/bin/bash

############################################################################################################
# Script Name: detect_failed_assemblies.sh
# Description: Identifies failed library IDs from a PBS error log by comparing with an accession list.
#              Uses metadata to auto-detect the list unless overridden. Output can be IDs or log files.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------------------
# Help Function
# ----------------------------------------

show_help() {
  echo -e "\n\033[1;34mUsage:\033[0m"
  echo "  $0 -e job_pbs.err [-f accession_list.txt] [-t library_id|log_files]"
  echo ""
  echo "Compares a PBS error log to an accession list to identify failed libraries."
  echo "Outputs either the failed library IDs or their log file paths."
  echo ""
  echo -e "\033[1;34mOptions:\033[0m"
  echo "  -e    Path to PBS .err log file (required)"
  echo "  -f    Override auto-detected accession list file (optional)"
  echo "  -t    Output type: 'library_id' (default) or 'log_files'"
  echo "  -h    Show this help message"
  echo ""
  echo -e "\033[1;34mExamples:\033[0m"
  echo "  $0 -e logs/assemble_reads_chunk_01.err"
  echo "  $0 -e logs/assemble_reads_chunk_01.err -t log_files"
  echo "  $0 -e logs/assemble_reads_chunk_01.err -f accession_lists/setone.txt -t log_files"
  echo ""
  exit 1
}

# ----------------------------------------
# Argument Parsing
# ----------------------------------------

pbs_err=""
accession_list=""
output_type="library_id"

while getopts "e:f:t:h" opt; do
  case $opt in
    e) pbs_err="$OPTARG" ;;
    f) accession_list="$OPTARG" ;;
    t) output_type="$OPTARG" ;;
    h|*) show_help ;;
  esac
done

# ----------------------------------------
# Validation
# ----------------------------------------

if [[ -z "$pbs_err" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m -e <pbs.err> is required."
  show_help
fi

if [[ ! -f "$pbs_err" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m File not found: $pbs_err"
  exit 1
fi

if [[ "$output_type" != "library_id" && "$output_type" != "log_files" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Invalid output type: $output_type"
  echo "Valid options: library_id, log_files"
  exit 1
fi

# ----------------------------------------
# Auto-detect accession list if not provided
# ----------------------------------------

if [[ -z "$accession_list" ]]; then
  accession_list=$(awk '
    /----- JOB METADATA BEGIN -----/ { in_block=1; next }
    /----- JOB METADATA END -----/ { in_block=0 }
    in_block && /^ACCESSION_LIST_USED:/ { split($0, a, ": "); print a[2]; exit }
  ' "$pbs_err")

  if [[ -z "$accession_list" ]]; then
    echo -e "\033[1;31m❌ ERROR:\033[0m Could not auto-detect ACCESSION_LIST_USED from metadata in $pbs_err"
    exit 1
  fi
fi

if [[ ! -f "$accession_list" ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m Accession list file not found: $accession_list"
  exit 1
fi

# ----------------------------------------
# Extract IDs
# ----------------------------------------

completed_ids=$(grep "Task .*exited with status 0" "$pbs_err" | awk '{print $NF}' | sort)
mapfile -t all_ids < <(sort "$accession_list")
mapfile -t failed_ids < <(comm -23 <(printf "%s\n" "${all_ids[@]}") <(printf "%s\n" "$completed_ids"))

# ----------------------------------------
# Output
# ----------------------------------------

if [[ "${#failed_ids[@]}" -eq 0 ]]; then
  echo "✅ No failed assemblies detected."
  exit 0
fi

if [[ "$output_type" == "library_id" ]]; then
  printf "%s\n" "${failed_ids[@]}"
else
  log_dir=$(dirname "$pbs_err")
  job_base=$(basename "$pbs_err" | sed 's/_pbs\.err$//')

  for id in "${failed_ids[@]}"; do
    echo "${log_dir}/${job_base}_${id}.log"
  done
fi
