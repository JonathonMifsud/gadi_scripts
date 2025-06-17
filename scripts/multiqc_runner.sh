#!/bin/bash
############################################################################################################
# Script Name: multiqc_run.pbs
# Description: PBS script to generate a filtered MultiQC summary of FastQC results on Gadi.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

#PBS -N multiqc
#PBS -l ncpus=1
#PBS -l mem=8GB
#PBS -l walltime=01:00:00
#PBS -q normal
#PBS -l storage=gdata/${ROOT_PROJECT}+scratch/${ROOT_PROJECT}
#PBS -P ${ROOT_PROJECT}
#PBS -j oe

set -euo pipefail
trap 'echo "❌ ERROR at line $LINENO in MultiQC job" >&2' ERR

# ----------------------------------------
# Environment Setup
# ----------------------------------------

export PATH="/g/data/fo27/software/singularity/bin:$PATH"

base_dir="/scratch/${ROOT_PROJECT}/${USER_ID}/${PROJECT_NAME}"
fastqc_dir="${base_dir}/fastqc"
multiqc_dir="${base_dir}/multiqc"
log_dir="${base_dir}/logs"
log_date=$(date +%Y%m%d)
input_list="/scratch/${ROOT_PROJECT}/${USER_ID}/${PROJECT_NAME}/accession_lists/${INPUT_LIST}"


mkdir -p "$multiqc_dir" "$log_dir"

# ----------------------------------------
# Step 1: Validate Input List
# ----------------------------------------

if [[ -z "$input_list" || ! -f "$input_list" ]]; then
  echo "❌ ERROR: INPUT_LIST not set or file missing: $input_list"
  exit 1
fi

echo "📄 Filtering FastQC reports using accession list: $input_list"
readarray -t library_ids < "$input_list"

# ----------------------------------------
# Step 2: Build FastQC .zip File List for Selected Libraries
# ----------------------------------------

file_list=$(mktemp)
for lib in "${library_ids[@]}"; do
  find "$fastqc_dir" -type f -name "${lib}"'*.zip' >> "$file_list"
done

if [[ ! -s "$file_list" ]]; then
  echo "❌ ERROR: No FastQC .zip reports found for libraries in: $input_list"
  exit 1
fi

echo "🔍 Found $(wc -l < "$file_list") FastQC reports to include."

# ----------------------------------------
# Step 3: Write Clean MultiQC Config if Missing
# ----------------------------------------

config_file="${base_dir}/scripts/multiqc_config.yaml"

if [[ ! -f "$config_file" ]]; then
  cat > "$config_file" <<EOF
title: "FastQC Summary Report - ${PROJECT_NAME}"
report_comment: "Includes raw, trimmed, and unpaired reads from the libraries in the input list."

sample_names:
  replace:
    "_1.fastq.gz": " (raw R1)"
    "_2.fastq.gz": " (raw R2)"
    "_trimmed.fastq.gz": " (trimmed)"
    "_trimmed_R1.fastq.gz": " (trimmed R1)"
    "_trimmed_R2.fastq.gz": " (trimmed R2)"
    "_unpaired.fastq.gz": " (unpaired)"
    ".fastq.gz": ""

sp:
  save_data_files: true

table_columns_visible:
  FastQC:
    percent_gc: True
    percent_duplicates: True
    total_sequences: True
    filename: False
EOF

  echo "🛠️  Wrote default config to: $config_file"
else
  echo "📄 Using existing MultiQC config: $config_file"
fi

# ----------------------------------------
# Step 4: Run MultiQC
# ----------------------------------------

echo "🚀 Running MultiQC..."
run_multiqc.sh multiqc --file-list "$file_list" \
        --outdir "$multiqc_dir"_"${log_date}" \
        --filename multiqc_summary_"${log_date}".html \
        --config "$config_file"

echo ""
echo "✅ MultiQC summary created at:"
echo "   ${multiqc_dir}/multiqc_summary_${log_date}.html"
