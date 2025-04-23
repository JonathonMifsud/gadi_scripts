#!/bin/bash
# download_sra_worker.sh
# Download and post-process a single SRA library.

set -euo pipefail

library_id="$1"
log_date=$(date +%Y%m%d)
script_name=$(basename "$0")
script_base="${script_name%.*}"

# Configurable paths
root_project="${ROOT_PROJECT:-fo27}"
user="${USER_ID:-jm8761}"
project="${PROJECT_NAME:-mytest}"
inpath="/scratch/${root_project}/${user}/${project}/raw_reads"

mkdir -p "$inpath"
cd "$inpath" || exit 1

log_file="${inpath}/${script_base}_${library_id}_${log_date}.log"
exec > "$log_file" 2>&1

# Load modules
module load aspera/4.4.1
export PATH="/g/data/${root_project}/software/singularity/bin:$PATH"

echo "▶️ Starting download: $library_id"

run_kingfisher.sh kingfisher get -r "$library_id" \
  -m ena-ascp ena-ftp prefetch aws-http aws-cp \
  --force --prefetch-max-size 100000000 \
  --output-form -fat-possibilities fastq.gz fastq

# Handle single-end files
if [[ -f "$library_id.fastq" || -f "$library_id.sra.fastq" ]]; then
  gzip -c "$library_id.fastq" > "$library_id.fastq.gz" 2>/dev/null || \
  gzip -c "$library_id.sra.fastq" > "$library_id.fastq.gz"
  rm -f "$library_id.fastq" "$library_id.sra.fastq"
fi

# Handle paired-end files
if [[ -f "${library_id}_1.fastq" || -f "${library_id}.sra_1.fastq" ]]; then
  gzip -c "${library_id}_1.fastq" > "${library_id}_1.fastq.gz" 2>/dev/null || \
  gzip -c "${library_id}.sra_1.fastq" > "${library_id}_1.fastq.gz"
  gzip -c "${library_id}_2.fastq" > "${library_id}_2.fastq.gz" 2>/dev/null || \
  gzip -c "${library_id}.sra_2.fastq" > "${library_id}_2.fastq.gz"
  rm -f "${library_id}_1.fastq" "${library_id}_2.fastq" "${library_id}.sra_"*.fastq
fi

# Fix corrupt gzipped files
for f in "${library_id}"*.gz; do
  if ! gzip -t "$f"; then
    mv "$f" "${f}.corrupt"
    gzip -c "${f}.corrupt" > "$f"
    gzip -t "$f" || rm -f "$f"
  fi
done

# Cleanup temp files
rm -f "${library_id}".aria2* "${library_id}".aspera-ckpt* "${library_id}".partial*

echo "✅ Completed $library_id"
