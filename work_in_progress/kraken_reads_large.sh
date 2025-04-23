#!/bin/bash
###############################################################################################################
#                                            BatchArtemisSRAMiner                                             #
#                                                JCO Mifsud                                                   #
#                                                   2023                                                      #
###############################################################################################################

# Set the default values
queue="defaultQ"
project=""
root_project=""
db="/scratch/VELAB/Databases/kraken_db"  # Default database path
use_shm="yes"  # Default value for use_shm

show_help() {
    echo ""
    echo "Usage: $0 [-f file_of_accessions] [-s use_shm] [-d database] [-h]"
    echo "  -f file_of_accessions: Full path to text file containing library IDs, one per line. (Required)"
    echo "  -s use_shm: Set to 'yes' to copy database to /dev/shm, 'no' to use database directly from disk. (Optional, default: yes)"
    echo "  -d database: Full path to the custom Kraken2 database. (Optional, default: $db)"
    echo "  -h: Display this help message."
    echo ""
    echo "  Example:"
    echo "  $0 -f /project/$root_project/$project/accession_lists/mylibs.txt -d /custom/path/to/kraken_db -s yes"
    echo ""
    echo " Check the Github page for more information:"
    echo " https://github.com/JonathonMifsud/BatchArtemisSRAMiner "
    exit 1
}

while getopts "p:f:q:r:d:s:h" 'OPTKEY'; do
    case "$OPTKEY" in
    'p')
        project="$OPTARG"
        ;;
    'f')
        file_of_accessions="$OPTARG"
        ;;
    'q')
        queue="$OPTARG"
        ;;
    'r')
        root_project="$OPTARG"
        ;;
    'd')
        db="$OPTARG"  # Assign the database path
        ;;
    's')
        use_shm="$OPTARG"  # Assign the use_shm option
        ;;
    'h')
        show_help
        ;;
    '?')
        echo "INVALID OPTION -- ${OPTARG}" >&2
        show_help
        ;;
    ':')
        echo "MISSING ARGUMENT for option -- ${OPTARG}" >&2
        show_help
        ;;
    *)
        echo "Invalid option: -$OPTARG" >&2
        show_help
        ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$project" ]; then
    echo "ERROR: No project string entered. Use e.g., -p JCOM_pipeline_virome"
    show_help
fi

if [ -z "$root_project" ]; then
    echo "ERROR: No root project string entered. Use e.g., -r VELAB or -r jcomvirome"
    show_help
fi

if [ -z "$file_of_accessions" ]; then
    echo "ERROR: No accession list provided, please specify this with (-f)"
    show_help
else
    file_of_accessions=$(ls -d "$file_of_accessions")
fi

# Ensure the logs directory exists
mkdir -p "/project/$root_project/$project/logs"

# Submit the job
qsub -o "/project/$root_project/$project/logs/kraken_large_${project}_$(date '+%Y%m%d')_stdout.txt" \
    -e "/project/$root_project/$project/logs/kraken_large_${project}_$(date '+%Y%m%d')_stderr.txt" \
    -v "project=$project,file_of_accessions=$file_of_accessions,root_project=$root_project,db=$db,use_shm=$use_shm" \
    -q "$queue" \
    -P "$root_project" \
    /project/"$root_project"/"$project"/scripts/newdog_kraken_reads_large.pbs
