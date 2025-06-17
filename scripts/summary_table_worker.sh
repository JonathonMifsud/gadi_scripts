#!/bin/bash
set -euo pipefail
trap 'echo "❌ ERROR: Unexpected failure at line $LINENO. Exiting." >&2' ERR

# Environment variables normally passed via qsub
# export ROOT_PROJECT="fo27"
# export PROJECT_NAME="mytest"
# export USER_ID="jm8761"
# export ACCESSION_LIST="/scratch/fo27/jm8761/mytest/accession_lists/tem"
# export NT_RESULTS="/scratch/fo27/jm8761/mytest/blast_results/to_blast_nt_blastn_results.txt"
# export NR_RESULTS="/scratch/fo27/jm8761/mytest/blast_results/to_blast_nr_blastx_results.txt"
# export SKIP_MISSING="QUJVTkRBTkNFLE5SLE5U"  # base64 for "ABUNDANCE,NR,NT"

# ---------------- Console Colors ----------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# ----------------------------------------
# PBS Variables
# ----------------------------------------

root_project="${ROOT_PROJECT:?Missing ROOT_PROJECT}"
project="${PROJECT_NAME:?Missing PROJECT_NAME}"
user="${USER_ID:?Missing USER_ID}"
accession_file="${ACCESSION_LIST:?Missing ACCESSION_LIST}"
nt_file="${NT_RESULTS:?Missing NT_RESULTS}"
nr_file="${NR_RESULTS:?Missing NR_RESULTS}"
skip_missing="${SKIP_MISSING:-}"
skip_missing=$(echo "$skip_missing" | base64 --decode)

# ----------------------------------------
# Paths
# ----------------------------------------
base_dir="/scratch/${root_project}/${user}/${project}"
blast_dir="${base_dir}/blast_results"
abundance_dir="${base_dir}/abundance/final_abundance"
log_dir="${base_dir}/logs"
log_date=$(date +%Y%m%d)
summary_dir="${base_dir}/summary_tables/${accession_file##*/}_${log_date}/"

mkdir -p "$summary_dir" "$log_dir"

module load R/4.3.1
export PATH="/g/data/fo27/software/singularity/bin:$PATH"

# ---------------- TaxonKit DB Setup ----------------
taxonkit_base="/scratch/${root_project}/monthly_dbs"
selected_db=""
echo -e "${BLUE}🔍 Searching for valid TaxonKit taxonomy DB...${NC}"

for dbdir in "$taxonkit_base"/taxdmp.*; do
  [[ -d "$dbdir" ]] || continue
  if [[ -f "$dbdir/nodes.dmp" && -f "$dbdir/names.dmp" ]]; then
    selected_db="$dbdir"
    break
  fi
done

if [[ -z "$selected_db" ]]; then
  echo -e "${RED}❌ ERROR: No valid TaxonKit DB found in $taxonkit_base${NC}"
  exit 1
fi

export TAXONKIT_DB="$selected_db"
echo -e "${GREEN}✅ TAXONKIT_DB set to: $TAXONKIT_DB${NC}"
echo -e "\033[1;34m📘 Starting summary table for accession/library list $accession_file\033[0m"

# ----------------------------------------
# Helper Functions
# ----------------------------------------

should_skip() {
  local key="$1"
  [[ " ${skip_missing[*]} " =~ " ${key} " ]]
}

check_file() {
  local f="$1"
  local label="$2"
  if [[ ! -s "$f" ]]; then
    if should_skip "$label"; then
      echo "⚠️ Warning: Missing or empty $label file: $f (SKIP_MISSING set)"
      return 1
    else
      echo "❌ ERROR: Required file missing or empty: $f"
      exit 1
    fi
  fi
  return 0
}

annotate_and_cat() {
  local tag="$1"
  local suffix="$2"
  local combined="$3"

  echo "🔹 Combining $tag $suffix files..."
  local files=()
  local missing=0

  while IFS= read -r id; do
    file="${blast_dir}/${id}_${tag}_${suffix}"
    if [[ -s "$file" ]]; then
      outfile="${blast_dir}/${id}_anno_${tag}_${suffix}"
      awk -F'\t' -vOFS='\t' -v id="$id" '{ $1 = $1 "_" id }1' "$file" > "$outfile"
      files+=("$outfile")
    else
      echo "⚠️ Missing: $file"
      ((missing++))
    fi
  done < "$accession_file"

  if (( ${#files[@]} == 0 )); then
    if should_skip "${tag^^}"; then
      echo "⚠️ Skipping $tag $suffix due to SKIP_MISSING."
      return
    else
      echo "❌ ERROR: No valid $tag $suffix files found."
      exit 1
    fi
  fi

  cat "${files[@]}" > "$combined"
  rm "${files[@]}"
  echo "✅ Combined file: $combined (${#files[@]} files, ${missing} missing)"
}

combine_fasta() {
  local tag="$1"
  local combined="$2"

  echo "🔹 Combining $tag blastcontigs..."
  local files=()
  local missing=0

  while IFS= read -r id; do
    f="${blast_dir}/${id}_${tag}_blastcontigs.fasta"
    if [[ -s "$f" ]]; then
      files+=("$f")
    else
      echo "⚠️ Missing: $f"
      ((missing++))
    fi
  done < "$accession_file"

  if (( ${#files[@]} == 0 )); then
    if should_skip "${tag^^}"; then
      echo "⚠️ Skipping $tag contigs due to SKIP_MISSING."
      return
    else
      echo "❌ ERROR: No valid $tag contigs found."
      exit 1
    fi
  fi

  cat "${files[@]}" > "$combined"
  echo "✅ Combined contigs: $combined (${#files[@]} files, ${missing} missing)"
}

# ----------------------------------------
# Abundance Table
# ----------------------------------------

echo -e "\n📊 Creating combined abundance table..."
combined_abundance="${summary_dir}/combined_abundance_table.txt"
rm -f "$combined_abundance"

missing=0
while IFS= read -r id; do
  f="${abundance_dir}/${id}_RSEM.isoforms.results"
  if [[ -s "$f" ]]; then
    awk -F'\t' -vOFS='\t' -v id="$id" 'NR==1 {print; next} { $1 = $1 "_" id; print }' "$f" >> "$combined_abundance"
  else
    echo "⚠️ Missing: $f"
    ((missing++))
  fi
done < "$accession_file"

if [[ ! -s "$combined_abundance" ]]; then
  if should_skip "ABUNDANCE"; then
    echo "⚠️ Skipping abundance table due to SKIP_MISSING."
  else
    echo "❌ ERROR: No valid abundance files found."
    exit 1
  fi
else
  echo "✅ Abundance table: $combined_abundance"
fi

# ----------------------------------------
# Combine rvdb and RdRp Blast Results
# ----------------------------------------

annotate_and_cat "rdrp" "blastx_results.txt" "${summary_dir}/combined_rdrp_blastx_results.txt"
annotate_and_cat "rvdb" "blastx_results.txt" "${summary_dir}/combined_rvdb_blastx_results.txt"

combine_fasta "rdrp" "${summary_dir}/combined_rdrp_blastcontigs.fasta"
combine_fasta "rvdb" "${summary_dir}/combined_rvdb_blastcontigs.fasta"

cat "${summary_dir}/combined_rdrp_blastcontigs.fasta" "${summary_dir}/combined_rvdb_blastcontigs.fasta" > "${summary_dir}/combined_contigs.fasta" 2>/dev/null || true

# ----------------------------------------
# NT/NR Results Filtering
# ----------------------------------------

accession_ids=$(cut -f1 "$accession_file" | sort -u)

filter_blast_file() {
  local infile="$1"
  local outfile="$2"
  if [[ -s "$infile" ]]; then
    grep -Ff "$accession_file" "$infile" > "$outfile" || true
  else
    echo "⚠️ Missing input: $infile"
    > "$outfile"
  fi
}

nt_combined="${summary_dir}/combined_nt_blastn_results.txt"
nr_combined="${summary_dir}/combined_nr_blastx_results.txt"

filter_blast_file "$nt_file" "$nt_combined"
filter_blast_file "$nr_file" "$nr_combined"

# ----------------------------------------
# 🧪 Capture inputs for local R testing
# ----------------------------------------

debug_dump_dir="${summary_dir}/debug_joint_table_inputs"
mkdir -p "$debug_dump_dir"

echo "📦 Dumping input files for local R testing to: $debug_dump_dir"

cp "$nr_combined" "$debug_dump_dir/nr.tsv"
cp "$nt_combined" "$debug_dump_dir/nt.tsv"
cp "${summary_dir}/combined_rdrp_blastx_results.txt" "$debug_dump_dir/rdrp.tsv"
cp "${summary_dir}/combined_rvdb_blastx_results.txt" "$debug_dump_dir/rvdb.tsv"
cp "$combined_abundance" "$debug_dump_dir/abundance.tsv"
cp "${base_dir}/read_count/${project}_accessions_reads" "$debug_dump_dir/readcounts.csv"
cp "/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.info" "$debug_dump_dir/rdrp_tax.tsv"

# Create a run script
cat > "$debug_dump_dir/run_local_test.sh" <<EOF
#!/bin/bash
Rscript create_blast_joint_table.R \\
  --nr nr.tsv \\
  --nt nt.tsv \\
  --rdrp rdrp.tsv \\
  --rvdb rvdb.tsv \\
  --abundance abundance.tsv \\
  --readcounts readcounts.csv \\
  --rdrp_tax rdrp_tax.tsv \\
  --output test_output.csv \\
  --multi_lib
EOF
chmod +x "$debug_dump_dir/run_local_test.sh"

# ----------------------------------------
# Run R: Create Joint Table
# ----------------------------------------

echo -e "\n🧪 Creating joint blast summary table..."

Rscript -e '
.libPaths("/g/data/fo27/software/other_software/r_packages/r_4.3.1");
args <- commandArgs(trailingOnly = TRUE);
source(file.path("'${base_dir}'", "scripts", "create_blast_joint_table.R"), chdir = TRUE)
main(
  nr = "'${nr_combined}'",
  nt = "'${nt_combined}'",
  rdrp = "'${summary_dir}/combined_rdrp_blastx_results.txt'",
  rvdb = "'${summary_dir}/combined_rvdb_blastx_results.txt'",
  abundance = "'${combined_abundance}'",
  readcounts = "'${base_dir}/read_count/${project}_accessions_reads'",
  output = "'${summary_dir}/temp_joint_blast_table'",
  rdrp_tax = "'/g/data/fo27/databases/blast/RdRp-scan/RdRp-scan_0.90.info'",
  multi_lib = TRUE
)
'

# ----------------------------------------
# TaxonKit: Get Lineage (before filtering)
# ----------------------------------------

echo -e "\n🧬 Assigning lineage with TaxonKit..."

taxid_file="${summary_dir}/temp_joint_blast_table_taxids"
lineage_file="${summary_dir}/temp_lineage_table"

awk -F'\t' '{print $5}' "${summary_dir}/temp_joint_blast_table" | grep -Ev '^\s*$' | sort -u > "$taxid_file"

if [[ ! -s "$taxid_file" ]]; then
  echo "⚠️ No taxids found in blast table. Skipping lineage step."
else
  run_taxonkit.sh taxonkit lineage "$taxid_file" --data-dir "$TAXONKIT_DB" |
    awk '$2 > 0' |
    cut -f 2- |
    run_taxonkit.sh taxonkit reformat --output-ambiguous-result \
                      --data-dir "$TAXONKIT_DB" \
                      -I 1 \
                      -r "Unassigned" \
                      -R "missing_taxid" \
                      --fill-miss-rank \
                      -f "{k}\t{p}\t{c}\t{o}\t{f}\t{g}\t{s}" |
    run_csvtk.sh csvtk add-header -t -n "taxid,lineage,kingdom,phylum,class,order,family,genus,species" > "$lineage_file"

  if [[ -s "$lineage_file" ]]; then
    echo -e "${GREEN}✅ Lineage file created: $lineage_file${NC}"
  else
    echo -e "${RED}❌ Lineage table is empty. Something went wrong with TaxonKit.${NC}"
    exit 1
  fi
fi


# ----------------------------------------
# Run R: Filter Table
# ----------------------------------------

echo -e "\n🧬 Filtering final summary table..."

Rscript -e '
.libPaths("/g/data/fo27/software/other_software/r_packages/r_4.3.1");
args <- commandArgs(trailingOnly = TRUE);
source(file.path("'${base_dir}'", "scripts", "filter_blast_table.R"), chdir = TRUE)
main(
  blast_table = "'${summary_dir}/temp_joint_blast_table'",
  output = "'${summary_dir}/${project}_complete_blast_summary_table_${log_date}'"
)
'


echo -e "\n\033[1;32m✅ Summary table creation complete!\033[0m"
echo "📁 Output directory: $summary_dir"
