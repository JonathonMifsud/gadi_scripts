#!/bin/bash

############################################################################################################
# Script Name: summary_table_runner.sh
# Description: Submits a PBS job to generate a summary table with blastx/abundance/taxonomy input validation
# GitHub: https://github.com/JonathonMifsud/gadi_scripts
############################################################################################################

set -uo pipefail
trap 'err=$?;
      echo -e "\n❌ ERROR: Command \"${BASH_COMMAND}\" failed with exit code $err at line $LINENO." >&2;
      echo "    → Script: $0" >&2;
      echo "    → Line:   $LINENO" >&2;
      exit $err' ERR

# ---------------- Project Metadata ----------------

project="mytest"
root_project="fo27"
user=$(whoami)

# ---------------- Console Colors ----------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# ---------------- PBS Settings ----------------

job_name="summary_table"
ncpus=1
mem="12GB"
walltime="01:00:00"
queue="normal"
storage="gdata/${root_project}+scratch/${root_project}"

# ---------------- Paths ----------------

base_dir="/scratch/${root_project}/${user}/${project}"
log_dir="${base_dir}/logs"
blast_dir="${base_dir}/blast_results"
accession_dir="${base_dir}/accession_lists"
abundance_dir="${base_dir}/abundance/final_abundance"
readcount_file="${base_dir}/read_count/${project}_accessions_reads.csv"
script_dir="${base_dir}/scripts"
pbs_script="${script_dir}/summary_table_worker.sh"

export PATH="/g/data/fo27/software/singularity/bin:$PATH"


# ---------------- Help ----------------

brief_help() {
  echo -e "\n\033[1;34mUsage:\033[0m $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]"
  echo -e ""
  echo -e "For full help, run: \033[1m$0 -h\033[0m"
}

show_help() {
  echo -e ""
  echo -e "\033[1;34mUsage:\033[0m"
  echo -e "  $0 -f /scratch/${root_project}/${user}/${project}/accession_lists/accession_list.txt [options]"
  echo -e ""

  echo -e "This script submits a PBS job on Gadi to generate a final summary table of viral identification results."
  echo -e "It validates the presence of input files (BLAST, read counts, abundance), and submits a single-task PBS job"
  echo -e "to a specified queue for downstream R processing via a worker script."
  echo -e ""

  echo -e "\033[1;34mRequired:\033[0m"
  echo "  -f    Accession list text file (1 accession ID per line)."
  echo "        Can be absolute or relative to: ${accession_dir}"
  echo -e ""

  echo -e "\033[1;34mOptional:\033[0m"
  echo "  -n    NT BLASTN results file. Default: <accession>_nt_blastn_results.txt in ${blast_dir}"
  echo "  -b    NR BLASTX results file. Default: <accession>_nr_blastx_results.txt in ${blast_dir}"
  echo "  -s    Custom PBS worker script path. Default: ${pbs_script}"
  echo "  -h    Show this help message and exit."
  echo -e ""

  echo -e "\033[1;34mValidation Performed:\033[0m"
  echo "  - BLAST result files for NT and NR exist and are non-empty"
  echo "  - BLAST contigs FASTA files exist"
  echo "  - Read count file exists and all accessions are included"
  echo "  - Abundance quantification files exist per accession"
  echo "  - At least one RdRp and one RVDB result file is found"
  echo -e ""

  echo -e "\033[1;34mExample:\033[0m"
  echo -e "  Submit with default blast files inferred from accession list:"
  echo -e "    $0 -f my_accessions.txt"
  echo -e ""
  echo -e "  Submit with explicit result file paths:"
  echo -e "    $0 -f my_accessions.txt -n nt_result.txt -b nr_result.txt"
  echo -e ""

  echo -e "\033[1;33mNotes:\033[0m"
  echo "  - If some accessions are missing read counts or abundance results, you will be prompted before continuing."
  echo "  - This script reserves all CPUs and memory for a single threaded task."
  echo "  - Make sure your scratch and gdata directories are writable before launching."
  echo -e ""

  echo -e "\033[1;34mGitHub:\033[0m"
  echo "  https://github.com/JonathonMifsud/gadi_scripts"
  echo -e ""

  exit 0
}

if [[ $# -eq 0 ]]; then
  echo -e "\033[1;31m❌ ERROR:\033[0m No arguments provided."
  brief_help
  exit 1
fi


# ---------------- Inputs ----------------

accession_list=""
nt_results=""
nr_results=""
skip_missing=()

# ---------------- Argument Parsing ----------------

while getopts ":f:n:b:s:h" opt; do
  case $opt in
    f)
      [[ "$OPTARG" = /* ]] && accession_list="$OPTARG" || accession_list="${accession_dir}/$OPTARG"
      ;;
    n) nt_results="$OPTARG" ;;
    b) nr_results="$OPTARG" ;;
    s) pbs_script="$OPTARG" ;;
    h|*) show_help ;;
  esac
done


# ---------------- Validation Function ----------------
check_missing_taxid() {
    local label="$1"
    local file="$2"
    local col="$3"

    if [[ -s "$file" ]]; then
      echo "   ↪ Checking $label BLAST file: $file"
      local total_lines
      total_lines=$(wc -l < "$file")
      local blank_taxids
      blank_taxids=$(awk -F'\t' -v col="$col" '$col == "" || $col == "-" { count++ } END { print count+0 }' "$file")

      if (( blank_taxids > 0 )); then
        echo -e "${YELLOW}⚠️  WARNING: ${blank_taxids}/${total_lines} entries in $label are missing taxid values.${NC}"
        echo -e "${YELLOW}   This may affect taxonomy in the final table.${NC}"
        echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
        read -r || REPLY=""
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
          echo -e "${RED}🛑 Aborting.${NC}"
          exit 1
        fi
      else
        echo -e "${GREEN}✅ All taxid fields present in $label.${NC}"
      fi
    else
      echo -e "${YELLOW}⚠️  Skipping $label taxid check: file not found or empty ($file)${NC}"
    fi
}

input_check() {
  echo ""
  echo "Checking all required input files..."
  echo "Accession list: $accession_list"

  skip_missing=()

  [[ -z "$accession_list" || ! -f "$accession_list" ]] && {
    echo "❌ Accession list not found: $accession_list"
    exit 1
  }

  accession_base=$(basename "$accession_list" .txt)
  accession_count=$(wc -l < "$accession_list")
  echo "📊 Number of accessions: $accession_count"

  # Infer defaults
  nt_results="${nt_results:-${blast_dir}/${accession_base}_nt_blastn_results.txt}"
  nr_results="${nr_results:-${blast_dir}/${accession_base}_nr_blastx_results.txt}"
  nt_contigs="${blast_dir}/${accession_base}_nt_blastcontigs.fasta"
  nr_contigs="${blast_dir}/${accession_base}_nr_blastcontigs.fasta"

  echo "Expected NT BLAST file:        $nt_results"
  echo "Expected NR BLAST file:        $nr_results"
  echo "Expected NT contigs FASTA:     $nt_contigs"
  echo "Expected NR contigs FASTA:     $nr_contigs"
  echo "Expected Read Count file:      $readcount_file"
  echo ""

  missing_files=()
  [[ ! -s "$nt_results" ]] && missing_files+=("NT BLAST: $nt_results")
  [[ ! -s "$nr_results" ]] && missing_files+=("NR BLAST: $nr_results")
  [[ ! -s "$nt_contigs" ]] && missing_files+=("NT Contigs: $nt_contigs")
  [[ ! -s "$nr_contigs" ]] && missing_files+=("NR Contigs: $nr_contigs")

  readcount_ids=""
  if [[ ! -s "$readcount_file" ]]; then
    echo -e "\n${RED}❌ Read count file missing: $readcount_file${NC}"
    echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
    read -r || REPLY=""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      skip_missing+=("READCOUNT")
    else
      echo -e "${RED}🛑 Aborting.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}✅ Read count file found: $readcount_file${NC}"
    readcount_ids=$(cut -d',' -f1 "$readcount_file" | sed -E 's/_trimmed(_R[12])?\.fastq$//' | sort -u)
  fi

  if [[ -n "$readcount_ids" ]]; then
    echo -e "${BLUE}🔍 Validating accessions are present in the read count file...${NC}"
    missing_readcount_ids=()
    while IFS= read -r id; do
      if ! grep -qx "${id}" <<< "$readcount_ids"; then
        missing_readcount_ids+=("$id")
      fi
    done < "$accession_list"

    if (( ${#missing_readcount_ids[@]} > 0 )); then
      echo -e "\n${RED}❌ The following accession IDs are missing from the read count file:${NC}"
      echo -e "\n${YELLOW} If you haven't already make sure to run the read_count script ${NC}"
      for id in "${missing_readcount_ids[@]}"; do
        echo -e "   - ${RED}${id}${NC}"
      done
      echo ""
      echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
      read -r || REPLY=""
      if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        skip_missing+=("READCOUNT")
      else
        echo -e "${RED}🛑 Aborting.${NC}"
        exit 1
      fi
    else
      echo -e "${GREEN}✅ All accessions found in the read count file.${NC}"
    fi
  fi

  echo ""
  echo "🔍 Checking abundance files for each accession..."
  missing_abundance=()
  abundance_loaded=0
  while IFS= read -r id; do
    file="${abundance_dir}/${id}_RSEM.isoforms.results"
    echo "   ↪ Checking: $file"
    if [[ ! -s "$file" ]]; then
      missing_abundance+=("$file")
    else
      ((abundance_loaded++))
    fi
  done < "$accession_list"
  if (( ${#missing_abundance[@]} > 0 )); then
    echo -e "\n${RED}❌  The following abundance files are missing or empty:${NC}"
    for file in "${missing_abundance[@]}"; do
      echo -e "   - ${RED}${file}${NC}"
    done
    echo -e "\n${YELLOW} If you haven't already make sure to run the calculate_contig_abundance script ${NC}"
    echo ""
    echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
    read -r || REPLY=""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      skip_missing+=("ABUNDANCE")
    else
      echo -e "${RED}🛑 Aborting.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}✅ All abundance files present: $abundance_loaded found.${NC}"
  fi

  echo ""
  echo "Checking RdRp and RVDB BLAST result files..."
  rdrp_count=0
  rvdb_count=0
  while IFS= read -r id; do
    [[ -s "${blast_dir}/${id}_rdrp_blastx_results.txt" ]] && ((rdrp_count++))
    [[ -s "${blast_dir}/${id}_rvdb_blastx_results.txt" ]] && ((rvdb_count++))
  done < "$accession_list"

  if (( rdrp_count == 0 || rvdb_count == 0 || ${#missing_files[@]} > 0 )); then
    echo -e "\n🚨 ${RED}Missing or empty required files:${NC}"
    for file in "${missing_files[@]}"; do
      echo -e "   - ${RED}${file}${NC}"
    done
    (( rdrp_count == 0 )) && echo -e "   - ${RED}RdRp blast files: none found${NC}"
    (( rvdb_count == 0 )) && echo -e "   - ${RED}RVDB blast files: none found${NC}"
    echo ""
    echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
    read -r || REPLY=""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      [[ ! -s "$nt_results" ]] && skip_missing+=("NT")
      [[ ! -s "$nr_results" ]] && skip_missing+=("NR")
      [[ ! -s "$nt_contigs" ]] && skip_missing+=("NT")
      [[ ! -s "$nr_contigs" ]] && skip_missing+=("NR")
      (( rdrp_count == 0 )) && skip_missing+=("RDRP")
      (( rvdb_count == 0 )) && skip_missing+=("RVDB")
    else
      echo "🛑 Aborting."
      exit 1
    fi
  else
    echo -e "\n${GREEN}✅ All required files are present.${NC}"
  fi

  echo ""
  echo "🔍 Validating taxid fields in RVDB and NR BLAST results..."

  echo -e "\n🔍 Checking taxid fields in RVDB BLAST results (per accession)..."
  rvdb_missing_taxids=0
  rvdb_total_lines=0
  while IFS= read -r id; do
    file="${blast_dir}/${id}_rvdb_blastx_results.txt"
    if [[ -s "$file" ]]; then
      lines=$(awk 'END { print NR }' "$file")
      blanks=$(awk -F'\t' '$5 == "" || $5 == "-" { count++ } END { print count+0 }' "$file")
      (( rvdb_missing_taxids += blanks ))
      (( rvdb_total_lines += lines ))
      if (( blanks > 0 )); then
        echo -e "${YELLOW}⚠️  $blanks/${lines} entries missing taxid in: $file${NC}"
      fi
    fi
  done < "$accession_list"

  if (( rvdb_missing_taxids > 0 )); then
    echo -e "${YELLOW}⚠️  WARNING: ${rvdb_missing_taxids}/${rvdb_total_lines} total RVDB hits are missing taxids.${NC}"
    echo -e "${YELLOW}   This may affect taxonomy in the final table.${NC}"
    echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
    read -r || REPLY=""
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
      echo -e "${RED}🛑 Aborting.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}✅ All RVDB taxid fields are present.${NC}"
  fi

  check_missing_taxid "NR" "$nr_results" 5

  echo ""
  echo -e "${BLUE}${BOLD}📊 Summary:${NC}"
  echo "  - Accessions:           $accession_count"
  echo "  - RdRp BLAST results:   $rdrp_count"
  echo "  - RVDB BLAST results:   $rvdb_count"
  echo "  - Abundance files:      $abundance_loaded"
  printf " - Skip override flags: %s\\n" "${skip_missing[*]:-none}"
  echo ""
}

# ---------------- Perform Input Checks ----------------
input_check
# ---------------- Submit PBS Job ----------------

mkdir -p "$log_dir"
log_date=$(date +%Y%m%d)

skip_str_raw=$(printf "%s\n" "${skip_missing[@]}" | sort -u | paste -sd ',' -)
skip_str=$(echo -n "$skip_str_raw" | base64)

echo -e "\n Submitting summary table job to PBS..."

qsub -N "${job_name}_${accession_base}" \
     -o "${log_dir}/${job_name}_${accession_base}_${log_date}_pbs.out" \
     -e "${log_dir}/${job_name}_${accession_base}_${log_date}_pbs.err" \
     -l ncpus=$ncpus \
     -l mem=$mem \
     -l walltime=$walltime \
     -l storage=$storage \
     -q "$queue" -P "$root_project" \
     -v ROOT_PROJECT="$root_project",PROJECT_NAME="$project",USER_ID="$user",ACCESSION_LIST="$accession_list",NT_RESULTS="$nt_results",NR_RESULTS="$nr_results",SKIP_MISSING="$skip_str" \
     "${pbs_script}"

summary_dir="${base_dir}/summary_tables/${accession_list##*/}_${log_date}/"

# --- Parse and summarize walltime ---
IFS=: read -r hh mm ss <<< "$walltime"
total_walltime_secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))

# --- Final Summary ---
echo ""
echo ""
echo -e "✅ PBS job submitted. Logs at: $log_dir"
printf "   Walltime allocated:      %s (%s seconds)\n" "$walltime" "$total_walltime_secs"
echo "   Results will be stored in $summary_dir."