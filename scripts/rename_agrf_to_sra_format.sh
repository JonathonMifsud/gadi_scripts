#!/bin/bash
###############################################################################################################
#                                       rename_agrf_fastq.sh (Gadi version)                                   #
###############################################################################################################

# Many thanks to Sabrina Sadiq for providing the code that this script is based on!

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# ----------------------------
# Default Variables
# ----------------------------
project=""
root_project=""
user=$(whoami)

path_to_files=""
agrf_string=""
auto_mode=false

# ----------------------------
# Help Function
# ----------------------------
usage() {
    echo -e "\n\033[1;34mUsage:\033[0m $0 -p <path_to_fastqs> -a <AGRF_string> [-y]"
    echo ""
    echo "Renames paired-end AGRF FastQ files to follow SRA-style naming (e.g. SRRxxxxxx_1.fastq.gz)."
    echo ""
    echo -e "\033[1;34mRequired:\033[0m"
    echo "  -p    Path to directory containing FastQ files"
    echo "  -a    AGRF flowcell string to remove (e.g. HLG3YDSX3)"
    echo ""
    echo -e "\033[1;34mOptional:\033[0m"
    echo "  -y    Run in non-interactive mode (auto-confirm all renames)"
    echo ""
    echo -e "\033[1;34mExample:\033[0m"
    echo "  $0 -p /scratch/${root_project}/${user}/${project}/raw_reads -a HLG3YDSX3"
    echo "  $0 -p ./fastqs -a HLP2ABCX7 -y"
    echo ""
    exit 1
}

# ----------------------------
# Parse Arguments
# ----------------------------
while getopts "p:a:yh" opt; do
    case "$opt" in
        p) path_to_files="$OPTARG" ;;
        a) agrf_string="$OPTARG" ;;
        y) auto_mode=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ----------------------------
# Validate Input
# ----------------------------
if [[ -z "$path_to_files" || -z "$agrf_string" ]]; then
    echo -e "\033[1;31m❌ ERROR:\033[0m Both -p and -a options are required."
    usage
fi

if [[ ! -d "$path_to_files" || ! -r "$path_to_files" ]]; then
    echo -e "\033[1;31m❌ ERROR:\033[0m Invalid or unreadable directory: $path_to_files"
    exit 1
fi

# ----------------------------
# File Renaming Logic
# ----------------------------
echo -e "\n🔍 Scanning directory: $path_to_files"

for file in "$path_to_files"/*R*.fastq.gz; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file")

        renamed="${filename/_R1.fastq.gz/_1.fastq.gz}"
        renamed="${renamed/_R2.fastq.gz/_2.fastq.gz}"

        # Remove AGRF flowcell-style ID block
        renamed=$(sed -r "s/(${agrf_string}_[A-Za-z0-9]+-[A-Za-z0-9]+)//" <<< "$renamed")

        # Fix double underscores or underscore hashes
        renamed=$(sed 's/_/#/g' <<< "$renamed")
        renamed=$(sed 's/\(.*\)#/\1_/' <<< "$renamed")
        renamed=$(sed 's/#//g' <<< "$renamed")

        new_file="$path_to_files/$renamed"

        echo -e "\nOriginal: \033[0;36m$file\033[0m"
        echo -e "Renamed:  \033[0;32m$new_file\033[0m"

        if [[ "$auto_mode" = true ]]; then
            mv "$file" "$new_file" && echo "✅ Renamed."
        else
            read -p "Rename this file? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                mv "$file" "$new_file" && echo "✅ Renamed."
            else
                echo "⏭️ Skipped."
            fi
        fi
    fi
done
