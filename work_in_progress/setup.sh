#!/bin/bash
###############################################################################################################
#                                            BatchArtemisSRAMiner                                             #   
#                                                JCO Mifsud                                                   # 
#                                                   2023                                                      # 
###############################################################################################################

# This script sets up a project with a specified structure in the provided root directory.
# It also moves all files from the current directory to the project's script directory 
# and adds the project name in file names and file contents so that the scripts are unique to the project.

# -------------------------------------------------------------------------
# USER-DEFINED SECTION – EDIT THIS: #
# -------------------------------------------------------------------------
# Root NCI project code (e.g., fo27 - but try to use your own!!)
root_project=""
# Project name (e.g., batvirome)
project=""
# email address 
email=""
# -------------------------------------------------------------------------

# 🚫 DO NOT EDIT BELOW THIS LINE
# Check if the required variables are set
if [[ -z "$root_project" || -z "$project" || -z "$email" ]]; then
    echo "Error: Please set the root_project, project, and email variables in the script."
    exit 1
fi

# Define directory paths for convenience
project_dir="/project/${root_project}/${project}"
scratch_dir="/scratch/${root_project}/${project}"

# Create project directories in /project and /scratch
# The -p option creates parent directories as needed and doesn't throw an error if the directory already exists.
echo "Creating project directories..."
mkdir -p "${project_dir}"/{scripts,accession_lists,adapters,logs,environments,ccmetagen,blast_results,annotation,mapping,contigs/{final_logs,final_contigs},fastqc,read_count}
mkdir -p "${scratch_dir}"/{abundance,read_count,raw_reads,trimmed_reads}
mkdir -p "${scratch_dir}"/abundance/final_abundance

# Move all files from the current directory to the project's scripts directory
echo "Moving files to the project's scripts directory..."
mv ./* "${project_dir}/scripts"
mv ../environments/* "${project_dir}/environments/"
mv ../adapters/* "${project_dir}/adapters/"

# Navigate to the project's scripts directory
cd "${project_dir}/scripts" || exit

# Prefix all .sh and .pbs files with the project name
echo "Renaming .sh and .pbs files to include project prefix..."
for f in *.sh *.pbs; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if [[ "$base" != "${project}_"* ]]; then
        mv "$f" "${project}_$f"
        echo "🔁 Renamed: $f → ${project}_$f"
    fi
done
# Update the contents of the scripts to replace project-specific strings
echo "Updating script contents with project-specific strings..."

# Replace placeholder variable assignments in the scripts with actual values
echo "Injecting project-specific variables into script headers..."
for script in *.sh *.pbs; do
    [[ -f "$script" ]] || continue  # Skip if no match
    sed -i "s/^project=\"\"/project=\"$project\"/" "$script"
    sed -i "s/^root_project=\"\"/root_project=\"$root_project\"/" "$script"
    sed -i "s/^email=\"\"/email=\"$email\"/" "$script"
    echo "Updated variables in: $script"
done

# Notify user about the project and scratch directory paths
echo "Project setup completed successfully."
echo "Project directory: ${project_dir}"
echo "Scratch directory: ${scratch_dir}"