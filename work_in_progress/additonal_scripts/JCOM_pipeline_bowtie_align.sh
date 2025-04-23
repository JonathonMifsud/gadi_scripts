#!/bin/bash

# Shell wrapper script to run STAR alignments for project folder

root_project=jcomvirome
project=newdog
queue=defaultQ

while getopts "p:f:q:r:" 'OPTKEY'; do
    case "$OPTKEY" in
            'p')
                project="$OPTARG"
                ;;
            'f')
                mapping_spreadsheet="$OPTARG"
                ;;
            'q')
                queue="$OPTARG"
                ;;
            'r')
                root_project="$OPTARG"
                ;;                    
            '?')
                echo "INVALID OPTION -- ${OPTARG}" >&2
                exit 1
                ;;
            ':')
                echo "MISSING ARGUMENT for option -- ${OPTARG}" >&2
                exit 1
                ;;
    esac
done
shift $(( OPTIND - 1 ))

if [ "$project" = "" ]; then
    echo "No project string entered. Use -p 1_dogvirome or -p 2_sealvirome"
    exit 1
fi

if [ "$root_project" = "" ]; then
    echo "No root project string entered. Use -r VELAB or -r jcomvirome"
    exit 1
fi

if [ "$mapping_spreadsheet" = "" ]; then
    echo "No file containing files to run specified."
    exit 1   
fi

# Set job time and queue project based on queue
case "$queue" in
    "defaultQ"|"highmem"|"large")
        job_time="walltime=48:00:00"
        queue_project="jcomvirome"
        ;;
    "scavenger")
        job_time="walltime=4:00:00"
        queue_project="jcomvirome"
        ;;
    "alloc-eh")
        job_time="walltime=4:00:00"
        queue_project="VELAB"
        ;;
    *)
        echo "Invalid queue specified."
        exit 1
        ;;
esac

# Determine the number of jobs needed based on the length of input
jMax=$(wc -l < "$mapping_spreadsheet")
jIndex=$(expr $jMax - 1)
jPhrase="0-$jIndex"

# Handle case where only one job is needed
if [ "$jPhrase" == "0-0" ]; then
    jPhrase="0-1"
fi

# Submit the PBS job array
qsub -J "$jPhrase" \
    -o "/project/$root_project/$project/logs/bowtie_align_^array_index^_$project_$(date '+%Y%m%d')_stdout.txt" \
    -e "/project/$root_project/$project/logs/bowtie_align_^array_index^_$project_$(date '+%Y%m%d')_stderr.txt" \
    -v "project=$project,mapping_spreadsheet=$mapping_spreadsheet,root_project=$root_project" \
    -q "$queue" \
    -l "$job_time" \
    -P "$root_project" \
    /project/"$root_project"/"$project"/scripts/"$project"_bowtie_align.pbs
