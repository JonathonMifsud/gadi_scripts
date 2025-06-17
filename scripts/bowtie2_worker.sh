#!/bin/bash

############################################################################################################
# Script Name: bowtie_worker.sh
# Description: Worker script to map reads using Bowtie2 on Gadi, with custom inputs from CSV.
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# --- Detect manual execution ---
if [[ -z "${PBS_JOBID:-}" ]]; then
  echo "⚠️ WARNING: This script is intended to be run via PBS."
  echo "Please use the runner script to submit jobs (e.g., bowtie_runner.sh)."
  echo ""
fi

# --- Environment variables from qsub -v ---
project="${PROJECT_NAME}"
root_project="${ROOT_PROJECT}"
user=$(whoami)
CPU="${NCPUS_PER_TASK}"
export PATH="/g/data/fo27/software/singularity/bin:$PATH"
# --- Input check ---
if [[ $# -lt 1 ]]; then
  echo "❌ ERROR: No CSV line input provided to $0"
  exit 1
fi

input_line="$1"

# --- Base paths ---
base_dir="/scratch/${root_project}/${user}/${project}"
trimmed_dir="${base_dir}/trimmed_reads"
mapping_dir="${base_dir}/mapping"
reference_dir="${mapping_dir}/reference"
log_dir="${base_dir}/logs"

mkdir -p "${mapping_dir}" "${log_dir}"
cd "${mapping_dir}" || exit 1
log_date=$(date +%Y%m%d)
jobname="${PBS_JOBNAME:-manual_bowtie}"

# --- Parse CSV line ---
IFS=',' read -r library_id reference_fasta minid <<< "$input_line"
if [[ -z "$library_id" || -z "$reference_fasta" || -z "$minid" ]]; then
  echo "❌ ERROR: Malformed CSV line: $input_line"
  exit 1
fi

# --- Set up filenames ---
sanitized_library=$(echo "$library_id" | tr ';' '_')
reference_path="${reference_dir}/${reference_fasta}"
reference_index="${reference_path}_index"
out_prefix="${mapping_dir}/${sanitized_library}_${reference_fasta}_${minid}"

fq_out="${out_prefix}_mapped.fq"
sam_out="${out_prefix}_mapped.sam"
bam_out="${out_prefix}_mapped.bam"
bam_sorted="${out_prefix}_mapped_sorted.bam"
bam_index="${bam_sorted}.bai"
bam_filtered="${out_prefix}_mapped_only.bam"
flagstat_csv="${out_prefix}_flagstat_output.csv"
coverage_txt="${out_prefix}_coverage.txt"
raw_coverage_txt="${out_prefix}_raw_coverage.txt"

log_file="${log_dir}/${jobname}_${log_date}_${sanitized_library}.log"
exec > "${log_file}" 2>&1

echo "📌 Mapping: $library_id → $reference_fasta at identity ≥ $minid"

# --- Validate reference ---
if [[ ! -f "$reference_path" ]]; then
  echo "❌ ERROR: Reference FASTA not found: $reference_path"
  exit 1
fi

# --- Build Bowtie2 index ---
if [[ ! -f "${reference_index}.1.bt2" ]]; then
  echo "🔧 Building Bowtie2 index..."
  bowtie2-build "$reference_path" "$reference_index"
else
  echo "✅ Reusing existing index: $reference_index"
fi

# --- Prepare reads ---
fq1_list=()
fq2_list=()

IFS=';' read -ra libs <<< "$library_id"
for lib in "${libs[@]}"; do
  fq1="${trimmed_dir}/${lib}_trimmed_R1.fastq.gz"
  fq2="${trimmed_dir}/${lib}_trimmed_R2.fastq.gz"
  if [[ ! -f "$fq1" || ! -f "$fq2" ]]; then
    echo "❌ ERROR: Missing read files for library: $lib"
    exit 1
  fi
  fq1_list+=("$fq1")
  fq2_list+=("$fq2")
done

fq1_combined=$(IFS=','; echo "${fq1_list[*]}")
fq2_combined=$(IFS=','; echo "${fq2_list[*]}")

# --- Run Bowtie2 ---
echo "🚀 Running Bowtie2 alignment..."
run_bowtie.sh bowtie2 -x "$reference_index" \
        -1 "$fq1_combined" \
        -2 "$fq2_combined" \
        -S "$sam_out" \
        --very-sensitive \
        --threads "$CPU" \
        --reorder

# --- Convert SAM → BAM ---
echo "📥 Converting SAM to BAM..."
run_samtools.sh samtools view -bS "$sam_out" > "$bam_out"
rm "$sam_out"

# --- Sort BAM ---
echo "🧪 Sorting BAM..."
run_samtools.sh samtools sort -@ "$CPU" -m 5G "$bam_out" -o "$bam_sorted"
rm "$bam_out"

# --- Index BAM ---
echo "📌 Indexing BAM..."
run_samtools.sh samtools index "$bam_sorted"

# --- Flagstat Report ---
echo "📊 Running flagstat..."
run_samtools.sh samtools flagstat "$bam_sorted" | tee "${flagstat_csv}.raw" | awk -v seq_name="$sanitized_library" '
/^[0-9]+ \+ [0-9]+ mapped / {mapped=$1}
/paired in sequencing/ {paired=$1}
/properly paired/ {properly_paired=$1}
/with itself and mate mapped/ {mate_mapped=$1}
/singletons/ {singletons=$1}
END {
    print "Sequence, File, Mapped, Paired, Properly Paired, Mate Mapped, Singletons"
    print seq_name "," FILENAME "," mapped "," paired "," properly_paired "," mate_mapped "," singletons
}' > "$flagstat_csv"

# --- Coverage Depth ---
echo "📈 Calculating average depth..."
run_samtools.sh samtools depth -a "$bam_sorted" > "$raw_coverage_txt"
awk -v fname="$(basename "$bam_sorted")" '{sum+=$3} END { print fname "," sum/NR }' "$raw_coverage_txt" > "$coverage_txt"

# --- Filter BAM for mapped reads only ---
run_samtools.sh samtools view -b -F 4 "$bam_sorted" > "$bam_filtered"

echo "✅ Bowtie2 mapping complete."
echo "Final BAM: $bam_sorted"
echo "Flagstat CSV: $flagstat_csv"
echo "Coverage: $coverage_txt"
