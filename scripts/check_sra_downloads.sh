#!/bin/bash
###############################################################################################################
#                               Gadi-Compatible SRA Download Check Script                                     #
###############################################################################################################

set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# -------------------------
# Default Project Settings
# -------------------------
project="mytest"
root_project="fo27"
user=$(whoami)

# -------------------------
# Help Function
# -------------------------
show_help() {
    echo ""
    echo -e "\033[1;34mUsage:\033[0m $0 -f file_of_accessions -d raw_reads_dir"
    echo ""
    echo "This script checks whether all SRA accessions listed in a file have been correctly downloaded."
    echo "It is Gadi-compatible and assumes downloads follow the Kingfisher pipeline output patterns."
    echo ""
    echo -e "\033[1;34mRequired:\033[0m"
    echo "  -f    Full path to text file containing accession IDs (one per line)"
    echo "  -d    Full path to directory containing downloaded FASTQ files"
    echo ""
    echo -e "\033[1;34mExample:\033[0m"
    echo "  $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/setone.txt \\"
    echo "     -d /scratch/${root_project}/${user}/${project}/raw_reads"
    echo ""
    echo "GitHub: https://github.com/JonathonMifsud/BatchArtemisSRAMiner"
    exit 1
}

# -------------------------
# Argument Parsing
# -------------------------
while getopts "d:f:h" opt; do
    case "$opt" in
        d) directory="$OPTARG" ;;
        f) file_of_accessions="$OPTARG" ;;
        h) show_help ;;
        *) echo "Invalid option: -$OPTARG" >&2; show_help ;;
    esac
done

if [[ -z "${directory:-}" || -z "${file_of_accessions:-}" ]]; then
    echo -e "\033[1;31m❌ ERROR:\033[0m Missing required arguments."
    show_help
fi

# -------------------------
# Collect SRA IDs from Files
# -------------------------
echo "🔍 Scanning downloaded FASTQ files in: $directory"

ls "$directory"/*.fastq.gz 2>/dev/null | \
    perl -ne '$_ =~ s[.*/(.*)][$1]; print "$_";' | \
    cut -d'_' -f1 | cut -d'.' -f1 | sort | uniq >"$directory/sra_ids.txt"

rm -f "$directory/missing_sra_ids.txt"

# -------------------------
# Check Each SRA ID Layout
# -------------------------
while read -r i; do
    layout="unknown"

    [[ -f "$directory/${i}.fastq.gz" && ! -f "$directory/${i}_1.fastq.gz" ]] && layout="single"
    [[ ! -f "$directory/${i}.fastq.gz" && -f "$directory/${i}_1.fastq.gz" ]] && layout="paired"
    [[ -f "$directory/${i}.fastq.gz" && -f "$directory/${i}_1.fastq.gz" ]] && layout="triple"

    if [[ "$layout" == "triple" ]]; then
        echo "⚠️ Found triple layout for $i — removing single-end file."
        rm -f "$directory/${i}.fastq.gz"
        layout="paired"
    fi

    if [[ "$layout" == "paired" && ! -f "$directory/${i}_2.fastq.gz" ]]; then
        echo "❌ Missing pair for $i — removing incomplete _1.fastq.gz"
        rm -f "$directory/${i}_1.fastq.gz"
        echo "$i" >>"$directory/missing_sra_ids.txt"
    fi

    if [[ "$layout" == "single" && ! -f "$directory/${i}.fastq.gz" ]]; then
        echo "❌ Missing single read file for $i"
        echo "$i" >>"$directory/missing_sra_ids.txt"
    fi
done < "$directory/sra_ids.txt"

# -------------------------
# Post-cleanup validation
# -------------------------
ls "$directory"/*.fastq.gz | \
    perl -ne '$_ =~ s[.*/(.*)][$1]; print "$_";' | \
    cut -d'_' -f1 | cut -d'.' -f1 | sort | uniq >"$directory/cleanup_sra_ids.txt"

grep -Fxvf "$directory/cleanup_sra_ids.txt" "$file_of_accessions" >>"$directory/missing_sra_ids.txt"

awk '!a[$0]++' "$directory/missing_sra_ids.txt" >"$directory/missing_sra_ids.txt.tmp" && \
mv "$directory/missing_sra_ids.txt.tmp" "$directory/missing_sra_ids.txt"

# -------------------------
# Final Reporting
# -------------------------
reset_color="\e[0m"
missing_count=$(grep -c . "$directory/missing_sra_ids.txt" || echo 0)

if [[ "$missing_count" -eq 0 ]]; then
    str="It's a Christmas miracle, all of the SRA ids were downloaded!"
    color1="\e[31m"
    color2="\e[32m"
    new_str=""
    for ((i = 0; i < ${#str}; i++)); do
        if ((i % 2 == 0)); then
            new_str+="${color1}${str:$i:1}"
        else
            new_str+="${color2}${str:$i:1}"
        fi
    done
    new_str+="${reset_color}"
    echo -e "$new_str"
else
    echo -e "\n\e[31mSome of the SRA ids were not downloaded or partially downloaded."
    echo -e "Missing count: ${missing_count}"
    echo -e "List of missing libraries:\n"
    cat "$directory/missing_sra_ids.txt"
    echo -e "\nYou can re-run downloads using missing_sra_ids.txt as input (-f) to your runner script."
    echo -e "$reset_color"

    temp_files=()
    for file in "$directory"/*; do
        if [[ $file =~ temp_SRR.*_file ]]; then
            temp_file=${file##*/}
            temp_file=${temp_file#temp_}
            temp_file=${temp_file%_file}
            temp_files+=("$temp_file")
        fi
    done

    if [[ ${#temp_files[@]} -ne 0 ]]; then
        echo -e "\e[33mWarning: Temporary or partial files detected for:"
        printf "%s\n" "${temp_files[@]}"
        echo -e "These may indicate failed downloads — inspect or delete before redownloading.\n${reset_color}"
    fi
fi

# Cleanup
rm -f "$directory/sra_ids.txt" "$directory/cleanup_sra_ids.txt"
