#!/bin/bash
# BatchArtemisSRAMiner (Gadi Setup)

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

########################################
# 🔧 USER-DEFINED SECTION – EDIT THIS: #
########################################

# Root NCI project code (e.g., fo27)
root_project=""

# Your NCI username or subdirectory (e.g., jm8761)
user=""

# Project name (e.g., JCOM_pipeline_virome)
project=""

# Your email
email=""

########################################
# 🚫 DO NOT EDIT BELOW THIS LINE       #
########################################

scratch_base="/scratch/${root_project}/${user}/${project}"

echo "Creating project directories under ${scratch_base} ..."
mkdir -p "${scratch_base}"/{scripts,accession_lists,adapters,logs,environments,multiqc,kraken,blast_results,mapping,fastqc,read_count}
mkdir -p "${scratch_base}"/contigs/{final_logs,final_contigs}
mkdir -p "${scratch_base}"/abundance/final_abundance
mkdir -p "${scratch_base}"/raw_reads "${scratch_base}"/trimmed_reads

echo "Moving files to ${scratch_base}/scripts ..."
mv ./* "${scratch_base}/scripts"
mv ../adapters/* "${scratch_base}/adapters/" 2>/dev/null

cd "${scratch_base}/scripts" || exit

echo "Renaming .sh and .pbs scripts to include project prefix..."
for f in *.sh *.pbs; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if [[ "$base" != "${project}_"* ]]; then
        mv "$f" "${project}_$f"
        echo "🔁 Renamed: $f → ${project}_$f"
    fi
done

echo "Replacing variables in script contents..."
for f in *.sh *.pbs; do
    [[ -f "$f" ]] || continue
    sed -i "s|project=\"\"|project=\"$project\"|g" "$f"
    sed -i "s|root_project=\"\"|root_project=\"$root_project\"|g" "$f"
    sed -i "s|email=\"\"|email=\"$email\"|g" "$f"
done

echo "✅ Project setup complete."
echo "Working directory: ${scratch_base}/scripts"
