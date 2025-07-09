# Gadi Scripts for Virus Discovery — Holmes Lab

A repo containing tools and shortcuts for virus discovery workflows for the Holmes Lab on Gadi.

### Installation

Clone the repository and run the setup script:

```bash
git clone https://github.com/JonathonMifsud/gadi_scripts.git
```

Enter the scripts folder:

```bash
cd gadi_scripts/scripts
```

Change the root, project and email parameters:

```bash
nano setup.sh
```

Run the setup script:

```bash
chmod +x ./setup.sh; ./setup.sh
```

### General 

Each general task you want to run is associated with a `runner`, `launcher` and a `worker` script. 

- The `runner` is what you run! It parsed user inputs (e.g. accession list, CPU/memory/walltime settings). 

- The `launcher` runs inside each PBS job and creates the list of tasks from the runner and orders the worker script.  
  The launcher is generic in that (basically) all scripts use the same one.

- The `worker` is what actually executes one task — typically for one library/accession/sample.

If you are unsure about what variables/files to use just call the help flag `-h` e.g.,

```bash
blastx_rdrp_runner.sh -h
```

You shouldn't really need to edit the scripts as most things like CPU, Walltime and Mem can be passed using flags!

All scripts will output logs in the `logs` folder!

**NOTE:** No `project/` dir on Gadi so everything is stored in `scratch`, you'll need to be careful to back everything up!

---

### Pipeline:

1. **Create an accession file**, plain text with the names of your libraries, one per line. These can either be SRA run IDs or Non-SRA libraries (see section *Non-SRA libraries*). This will be used as the main input for the scripts. 

   **If using SRA:**

   1.1 If these are SRA, download these using `download_sra_runner.sh`. Note all the scripts will be renamed to reflect your project name.

   1.2 Check that the raw reads have downloaded by looking in:

   ```
   /scratch/^your_root_project^/^your_project^/raw_reads
   ```

   You can use the `check_sra_downloads.sh` script to do this! Re-download any that are missing.

   **If not using SRA:**

   1.3 Place your `.fastq.gz` files in the `raw_reads` folder and rename if needed (see *Non-SRA libraries*).

2. **Run read trimming**: `trim_reads_runner.sh`  

   2.1 Trimming is currently set up for TruSeq3 PE and SE Illumina libs and will also trim Nextera (PE only).  

   2.2 Check that all read files are non-zero in size in:

   ```
   /scratch/^your_root_project^/^your_project^/trimmed_reads/
   ```

   2.3 It is advised to check trimming quality on at least a subset of samples using the included FastQC scripts:

   - `fastqc_runner.sh` — runs FastQC on raw and trimmed files  
   - `multiqc_runner.sh` — summarizes results - might be handy if there are alot of libs

   Also check the size of the trimmed read files to ensure that an excessive number of reads isn't being removed. Most importantly, check for adapter contamination.

3. **Run assembly**: `assemble_reads_runner.sh`  

   3.1 Check that all your contigs exist and are non-zero in the `contigs/final_contigs/` folder.

4. **Run the read count script**: `read_count_runner.sh`

5. **Run RdRp and RVDB blasts**:  
   - `blastx_rdrp_runner.sh`  
   - `blastx_rvdb_runner.sh`  
   These can be run simultaneously.

6. **Run NR and NT blasts** (after all of the above blasts are finished):  
   - `blastx_nr_runner.sh`  
   - `blastn_nt_worker.sh`  
   These will combine all of the hits and run a single BLAST.

7. **Summary table** — a work in progress, sorry :(

There are a bunch of other additional scripts for other things you may want to do!
---

### Non-SRA Libraries

You can also use the script with non-SRA libraries by cleaning the original raw read names.  The `rename_agrf_to_sra_format.sh` might be helpful for this!
For example:

Original filename:
```
hope_valley3_10_HWGFMDSX5_CCTGCAACCT-CTGACTCTAC_L002_R1.fastq.gz
```

Renamed to:
```
hpv3t10_1.fastq.gz
```

The main requirement is:
- Underscores are only used to separate the ID (`hpv3t10`) and the read direction (`1`)
- The "R" in `R1`/`R2` is removed.

---

### Differences from Artemis

- Many aspects of the job scheduling have been changed to fit Gadi.
- The scripts have been generally improved, including help functions (`-h`) and error handling.
- No need for Anaconda or Aspera installs anymore!
- Some extra scripts have been added.

---

### To Do

- Summary table script still needs some work  
- RVDB blast taxonomy is still an issue but the BLAST itself should work
