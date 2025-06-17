#!/usr/bin/env Rscript

# Author: Jonathon Mifsud (Gadi-compatible version)
# Description: Joins BLAST/abundance/taxonomy results into a unified table and extracts taxids.
setwd("/Users/jonmifsud/r_temp") # DELETE ME
# Load Packages ------------------------
suppressPackageStartupMessages({
  library(optparse)
  library(dplyr)
  library(vroom)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(readr)
})

# Error Utilities ------------------------
exit_with_error <- function(msg) {
  cat("❌ ERROR:", msg, "\n")
  quit(status = 1)
}

# Argument Parsing ------------------------
option_list <- list(
  make_option("--nr", type = "character", help = "NR blastx result file"),
  make_option("--nt", type = "character", help = "NT blastn result file"),
  make_option("--rdrp", type = "character", help = "RdRp blastx result file"),
  make_option("--rvdb", type = "character", help = "RVDB blastx result file"),
  make_option("--abundance", type = "character", help = "RSEM abundance file"),
  make_option("--readcounts", type = "character", help = "Read count file"),
  make_option("--rdrp_tax", type = "character", help = "RdRp taxonomy info"),
  make_option("--output", type = "character", help = "Output base filename"),
  make_option("--multi_lib", action = "store_true", default = FALSE, help = "Multiple libraries mode")
)

opt <- parse_args(OptionParser(option_list = option_list))

# Validate Inputs ------------------------
required <- c("nr", "nt", "rdrp", "rvdb", "abundance", "readcounts", "rdrp_tax", "output")
for (field in required) {
  path <- opt[[field]]
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    exit_with_error(paste("Missing or invalid:", field))
  }
}

# Load Input Files ------------------------
cat("📦 Reading input tables...\n")

nr <- vroom(opt$nr, col_names = c("contig", "length", "accession", "desc", "taxid", "ident", "region", "evalue"), delim = "\t", show_col_types = FALSE)
nt <- vroom(opt$nt, col_names = c("contig", "length", "accession", "desc", "taxid", "ident", "length2", "evalue"), delim = "\t", show_col_types = FALSE)
rdrp <- vroom(opt$rdrp, col_names = c("contig", "length", "accession", "desc", "ident", "region", "evalue"), delim = "\t", show_col_types = FALSE)
rvdb <- vroom(opt$rvdb, col_names = c("contig", "length", "accession", "desc", "ident", "region", "evalue"), delim = "\t", show_col_types = FALSE)
abundance <- vroom(opt$abundance, col_names = c("contig", "gene_id", "length", "effective_length", "expected_count", "TPM", "FPKM", "IsoPct"), show_col_types = FALSE)
readcounts <- vroom(opt$readcounts, col_names = FALSE, show_col_types = FALSE) |>
  mutate(value = str_trim(X1)) |>
  separate(value, into = c("library", "read_count"), sep = ",", convert = TRUE) |>
  select(library, read_count)
rdrp_tax <- vroom(opt$rdrp_tax, col_names = c("protein_accession", "viral_taxa", "description", "taxid", "host_species", "source"), show_col_types = FALSE)[-1, ]


#rvdb_tax <- vroom(opt$rvdb_tax, col_names = c("join_column", "source", "protein_accession", "source2", "nucl", "genomic_region", "organism", "taxid"), delim = "|", show_col_types = FALSE) |>
  #mutate(join_column = str_replace_all(join_column, "\\%", "\\|"))

# Helper Functions ------------------------
blastGetTopHit <- function(tbl) {
  tbl |>
    group_by(contig) |>
    filter(evalue == min(evalue)) |>
    ungroup()
}

blastCreateJoinTable <- function(nr, nt, rdrp, rvdb, abundance, readcounts, rdrp_tax, rvdb_tax) {
  table_nr <- blastGetTopHit(nr) |>
    rename_with(~ paste0("nr_", .)) |>
    select(-nr_region, -nr_length) |>
    distinct(nr_contig, .keep_all = TRUE)
  table_nt <- blastGetTopHit(nt) |>
    rename_with(~ paste0("nt_", .)) |>
    select(-nt_length) |>
    distinct(nt_contig, .keep_all = TRUE)
  table_rdrp <- blastGetTopHit(rdrp) |>
    rename_with(~ paste0("rdrp_", .)) |>
    select(-rdrp_region, -rdrp_length) |>
    distinct(rdrp_contig, .keep_all = TRUE)
  table_rvdb <- blastGetTopHit(rvdb) |>
    rename_with(~ paste0("rvdb_", .)) |>
    select(-rvdb_region, -rvdb_length) |>
    distinct(rvdb_contig, .keep_all = TRUE)

  table_abundance <- abundance |>
    filter(length != "length") |>
    select(contig, length, expected_count, FPKM) |>
    mutate(length = as.numeric(length), expected_count = as.numeric(expected_count), FPKM = as.numeric(FPKM)) |>
    mutate(library = str_remove(str_extract(contig, "len\\d+_.*"), "len\\d+_"))

  table_readcount <- readcounts |>
    mutate(library = str_remove_all(library, "_trimmed.*")) |>
    group_by(library) |>
    mutate(paired_read_count = sum(read_count)) |>
    ungroup() |>
    distinct(library, paired_read_count)

  table_rdrp <- table_rdrp |>
    mutate(rdrp_accession = if_else(!rdrp_accession %in% rdrp_tax$protein_accession, rdrp_desc, rdrp_accession)) |>
    left_join(rdrp_tax, by = c("rdrp_accession" = "protein_accession")) |>
    select(rdrp_contig, rdrp_accession, rdrp_desc, rdrp_ident, rdrp_evalue, viral_taxa, taxid, host_species, source) |>
    rename(rdrp_viral_taxa = viral_taxa, rdrp_taxid = taxid, rdrp_host_species = host_species, rdrp_source = source)

  table_rvdb <- table_rvdb |>
    left_join(rvdb_tax, by = c("rvdb_desc" = "join_column")) |>
    select(rvdb_contig, protein_accession, organism, rvdb_ident, rvdb_evalue, genomic_region, taxid) |>
    rename(rvdb_protein_accession = protein_accession, rvdb_organism = organism, rvdb_genomic_region = genomic_region, rvdb_taxid = taxid)

  table_abundance |>
    left_join(table_readcount, by = "library") |>
    filter(contig %in% table_rdrp$rdrp_contig | contig %in% table_rvdb$rvdb_contig) |>
    mutate(standarised_abundance_proportion = expected_count / paired_read_count) |>
    full_join(table_rdrp, by = c("contig" = "rdrp_contig")) |>
    left_join(table_rvdb, by = c("contig" = "rvdb_contig")) |>
    left_join(table_nt, by = c("contig" = "nt_contig")) |>
    left_join(table_nr, by = c("contig" = "nr_contig")) |>
    distinct(.keep_all = TRUE)
}

blastExtractTaxidFromJoinTable <- function(tbl) {
  tbl |>
    select(ends_with("taxid")) |>
    mutate(across(everything(), ~ str_replace_all(.x, ";.*", ""))) |>
    mutate(across(everything(), as.numeric)) |>
    pivot_longer(cols = everything(), values_to = "taxid", names_to = "source") |>
    select(taxid) |>
    distinct() |>
    drop_na()
}

# Generate Summary Table ------------------------
cat("🛠 Creating joint table...\n")
final_table <- blastCreateJoinTable(nr, nt, rdrp, rvdb, abundance, readcounts, rdrp_tax)
taxid_set <- blastExtractTaxidFromJoinTable(final_table)

write_delim(taxid_set, paste0(opt$output, "_taxids"), col_names = FALSE)
write_csv(final_table, opt$output)

cat("✅ Done. Output written to:", opt$output, "\n")
