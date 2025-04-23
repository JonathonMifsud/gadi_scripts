#!/bin/bash

# Common PBS options
pbs_header="#PBS -q copyq
#PBS -l walltime=00:40:00
#PBS -l mem=6GB
#PBS -l ncpus=1
#PBS -l storage=gdata/fo27
#PBS -o logs/
#PBS -e logs/
#PBS -S /bin/bash"

mkdir -p logs

# Each line is: output_path URL
while IFS= read -r line; do
    output=$(echo "$line" | awk '{print $3}')
    url=$(echo "$line" | awk '{print $4}')
    name=$(basename "$output" .sif)
    
    job_script=$(mktemp)
    echo "$pbs_header" > "$job_script"
    echo "#PBS -N pull_${name}" >> "$job_script"
    echo "" >> "$job_script"
    echo "module load singularity" >> "$job_script"
    echo "singularity pull $output $url" >> "$job_script"

    qsub "$job_script"
    echo "Submitted job: pull_${name}"
    sleep 5
done <<EOF
singularity pull /g/data/fo27/software/singularity/images/interproscan-5.55_88.0.sif https://depot.galaxyproject.org/singularity/interproscan:5.55_88.0--hec16e2b_1
singularity pull /g/data/fo27/software/singularity/images/kingfisher-0.4.1.sif https://depot.galaxyproject.org/singularity/kingfisher:0.4.1--pyh7cba7a3_0
singularity pull /g/data/fo27/software/singularity/images/prokka-1.14.6.sif https://depot.galaxyproject.org/singularity/prokka:1.14.6--pl5321hdfd78af_5
singularity pull /g/data/fo27/software/singularity/images/tracer-1.7.2.sif https://depot.galaxyproject.org/singularity/tracer:1.7.2--hdfd78af_0
singularity pull /g/data/fo27/software/singularity/images/trimmomatic-0.35.sif https://depot.galaxyproject.org/singularity/trimmomatic:0.35--hdfd78af_7
singularity pull /g/data/fo27/software/singularity/images/trinity-2.15.2.sif https://depot.galaxyproject.org/singularity/trinity:2.15.2--pl5321hdcf5f25_1
singularity pull /g/data/fo27/software/singularity/images/checkv-1.0.2.sif https://depot.galaxyproject.org/singularity/checkv:1.0.2--pyhdfd78af_0
EOF
