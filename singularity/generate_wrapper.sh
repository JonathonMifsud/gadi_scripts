[jm8761@gadi-login-04 scripts]$ cat generate_wrapper.sh
#!/bin/bash

# =============================================================================
# Singularity Wrapper Script Generator JM2025
# -----------------------------------------------------------------------------
# This script generates a Singularity wrapper script for running software inside a
# Singularity container. It dynamically determines the correct image version
# based on the config file and allows users to specify additional bind paths.
# -----------------------------------------------------------------------------

# =============================================================================
# CONFIGURATION
# =============================================================================
bin_dir="/g/data/fo27/software/singularity/bin"
config_file="/g/data/fo27/software/singularity/config/versions.txt"
image_dir="/g/data/fo27/software/singularity/images"
default_bind_paths="/g/data:/mnt/data"

# =============================================================================
# FUNCTIONS
# =============================================================================

# Display help information
show_help() {
    echo "Usage: $0 --software <name>"
    echo ""
    echo "This script generates a Singularity wrapper script for a specified software."
    echo "The wrapper ensures that the correct version of the software is used."
    echo ""
    echo "Options:"
    echo "  --software <name>        Specify the software name (e.g. diamond, blast, fastqc)"
    echo "  -h, --help               Show this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 --software blast"
    echo "  (Creates a wrapper script for 'blast' in $bin_dir)"
}

# Error handling function
error_exit() {
    echo "Error: $1"
    exit 1
}

# =============================================================================
# CHECKS & SETUP
# =============================================================================

# Ensure Singularity is installed or load it
if ! command -v singularity &> /dev/null; then
    echo "Singularity not found in PATH. Trying to load the module..."
    module load singularity
    if ! command -v singularity &> /dev/null; then
        error_exit "Singularity is still not available after 'module load'. Please check your environment."
    else
        echo "Singularity module loaded successfully."
    fi
fi

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

software_name=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --software)
            software_name="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$software_name" ]]; then
    error_exit "Please provide a software name using --software <name>."
fi

software_name=$(echo "$software_name" | tr '[:upper:]' '[:lower:]')  # Normalize case

# =============================================================================
# VALIDATION
# =============================================================================

mkdir -p "$bin_dir" || error_exit "Failed to create bin directory: $bin_dir"

if [ ! -f "$config_file" ]; then
    error_exit "Config file not found at $config_file. Please create it before using this script."
fi

if ! grep -q "^$software_name=" "$config_file"; then
    error_exit "No entry found for '$software_name' in $config_file.
Ensure the software is added to $config_file before generating a wrapper."
fi

# Check for duplicate entries of the software in the config file
matching_lines=$(grep "^$software_name=" "$config_file")
match_count=$(echo "$matching_lines" | wc -l)

if [ "$match_count" -gt 1 ]; then
    echo -e "\033[0;33m⚠ Warning:\033[0m Multiple entries found for '$software_name' in $config_file:"
    echo "$matching_lines"
    echo "Please review and keep only one entry to avoid unexpected behavior."
fi

script_path="$bin_dir/run_${software_name}.sh"

# =============================================================================
# CREATE WRAPPER SCRIPT JM2025
# =============================================================================

cat << EOF > "$script_path"
#!/usr/bin/env bash

# =============================================================================
# $software_name Wrapper Script for Singularity
# -----------------------------------------------------------------------------
# This script runs $software_name inside a Singularity container.
# It dynamically determines the correct image version based on the config file.
# Users can specify additional bind paths using the --bind_extra_paths option.
# =============================================================================

# Set paths
config_file="$config_file"
image_dir="$image_dir"
default_bind_paths="$default_bind_paths"
extra_bind_paths=()  # Array to store additional user-defined binds

# Define colors
BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Show help function
show_help() {
    echo -e "\${BOLD}Usage:\${RESET} \$0 [--bind_extra_paths <path>] [--] <command> [args]"
    echo ""
    echo -e "\${BOLD}Description:\${RESET}"
    echo -e "This wrapper runs commands inside the \${CYAN}$software_name\${RESET} Singularity container."
    echo -e "It ensures the correct version is used (from your config file) and allows extra bind paths."
    echo ""
    echo -e "\${BOLD}Wrapper Options:\${RESET}"
    echo -e "  \${GREEN}--bind_extra_paths <path>\${RESET}   Bind additional host paths (e.g. /scratch:/mnt/scratch)"
    echo -e "  \${GREEN}-h, --help\${RESET}                  Show this wrapper help and then internal tool help"
    echo ""
    echo -e "\${BOLD}Examples:\${RESET}"
    echo -e "  \${CYAN}\$0 -h\${RESET}"
    echo -e "      → Shows this wrapper's help and then an attempt to show top-level tool help (if applicable)"
    echo ""
    echo -e "  \${CYAN}/g/data/fo27/software/singularity/bin/run_fastqc.sh fastqc --version\${RESET}"
    echo -e "      → For single-command tools: runs 'fastqc --version' inside the container"
    echo ""
    echo -e "  \${CYAN}/g/data/fo27/software/singularity/bin/run_blast.sh blastn -query input.fa -db nt -out result.txt\${RESET}"
    echo -e "      → For suites like BLAST which don't have a top level function (blast): run the subfunction 'blastn' with its arguments inside the container"
    echo ""
    echo -e "\${BOLD}Important:\${RESET}"
    echo -e "  If the software (like BLAST) doesn't have a top-level command, don't run:"
    echo -e "      \${CYAN}\$0 -- --version\${RESET}"
    echo -e "  Instead, use:"
    echo -e "      \${CYAN}\$0 blastn --version\${RESET} or similar subcommands"
    echo ""
    echo -e "\${BOLD}Note:\${RESET}"
    echo -e "  Use \${GREEN}--\${RESET} only if you need to specify wrapper options from the tool command (unlikely)."
    echo -e "  For most usage, you can omit it and start directly with the command."
    echo ""
    echo -e "Please reach out to Jon (jonathon.mifsud1@gmail.com) if you have any questions or issues with the Singularity scripts."
    echo -e "\${BOLD}-------------------------------------------\${RESET}"
}

# Ensure Singularity is installed or load it
if ! command -v singularity &> /dev/null; then
    echo "Singularity not found in PATH. Trying to load the module..."
    module load singularity
    if ! command -v singularity &> /dev/null; then
        error_exit "Singularity is still not available after 'module load'. Please check your environment."
    else
        echo "Singularity module loaded successfully."
    fi
fi

# Ensure the config file exists
if [ ! -f "\$config_file" ]; then
    echo -e "\${RED}Error:\${RESET} Config file not found at \$config_file"
    exit 1
fi

# Read the software version from the config file
software_version=\$(grep "^$software_name=" "\$config_file" | cut -d '=' -f2)

# Validate that a version was found
if [ -z "\$software_version" ]; then
    echo -e "\${RED}Error:\${RESET} No version found for $software_name in \$config_file"
    exit 1
fi

# Construct the expected Singularity image path
image="\$image_dir/$software_name-\$software_version.sif"

# Check if the expected Singularity image exists
if [ ! -f "\$image" ]; then
    echo -e "\${RED}Error:\${RESET} $software_name image not found at \$image"
    echo -e "Run the update script to pull the latest image:"
    echo -e "  \${CYAN}bash /g/data/fo27/software/singularity/update_images.sh\${RESET}"
    exit 1
fi

# Show help if no arguments or help is requested
if [[ \$# -eq 0 ]]; then
    show_help
    exit 0
elif [[ "\$1" == "--help" || "\$1" == "-h" ]]; then
    show_help
    echo -e "\n\${BOLD}Now displaying internal tool help from inside the container:\${RESET}"
    echo "-------------------------------------------"
    # Try running the base tool only if it exists inside the container
    if singularity exec --bind "\$default_bind_paths" "\$image" which $software_name &> /dev/null; then
        singularity exec --bind "\$default_bind_paths" "\$image" $software_name --help
    else
        echo -e "\${RED}Note:\${RESET} '\$software_name' is not a valid command by itself."
        echo -e "Please call a specific subcommand directly, such as:"
        echo -e "  \${CYAN}\$0 blastn -query input.fa -db nt\${RESET}"
    fi

    exit 0
fi

# Reject unknown flags
if [[ "\$1" == -* && "\$1" != "--bind_extra_paths" ]]; then
    echo -e "\${RED}Error:\${RESET} Unknown option '\$1'"
    show_help
    exit 1
fi

# Parse command-line arguments
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --bind_extra_paths)
            if [[ -n "\$2" ]]; then
                extra_bind_paths+=("\$2")
                shift 2
            else
                echo -e "\${RED}Error:\${RESET} No path provided after --bind_extra_paths option"
                exit 1
            fi
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# Combine default and extra bind paths
bind_paths="\$default_bind_paths"
for path in "\${extra_bind_paths[@]}"; do
    host_path=\$(echo "\$path" | cut -d ':' -f1)
    if [ ! -d "\$host_path" ] || [ ! -r "\$host_path" ]; then
        echo -e "\${RED}Warning:\${RESET} Skipping \$path because you do not have read access."
    else
        bind_paths="\$bind_paths,\$path"
    fi
done

# Inform the user about the execution
echo -e "\n\${BOLD}-------------------------------------------\${RESET}"
echo -e "\${CYAN}$software_name Execution\${RESET}"
echo -e "\${BOLD}-------------------------------------------\${RESET}"
echo -e "\${BOLD}Version:\${RESET}        \$software_version"
echo -e "\${BOLD}Image:\${RESET}          \$image"
echo -e "\${BOLD}Binding Paths:\${RESET}  \$bind_paths"
echo -e "\${BOLD}-------------------------------------------\${RESET}"

# Warn if the first command is not found inside the container
if ! singularity exec --bind "\$bind_paths" "\$image" which "\$1" &> /dev/null; then
    echo -e "\${RED}Error:\${RESET} '\$1' is not a recognized command inside the container."
    # Check if the main software command is valid (i.e., it's a single-command tool)
    if singularity exec --bind "\$bind_paths" "\$image" which $software_name &> /dev/null; then
        echo -e "Try running: \${CYAN}\$0 --help\${RESET} for guidance."
    else
        echo -e "This software does not support a top-level command."
        echo -e "Please run a valid subcommand like: \${CYAN}\$0 blastn --help\${RESET}"
    fi
    exit 1
fi

if [[ \$# -eq 0 ]]; then
    echo -e "\${RED}Error:\${RESET} No command or arguments provided."
    echo -e "For example: \${CYAN}\$0 blastn -query input.fa -db nt -out result.txt\${RESET}"
    exit 1
fi

# Execute the software inside the Singularity container
singularity exec --bind "\$bind_paths" "\$image" "\$@"


# Capture the exit status of Singularity
exit_status=\$?

# Check if the command executed successfully
if [ \$exit_status -ne 0 ]; then
    echo -e "\${RED}Error:\${RESET} $software_name execution failed with exit code \$exit_status"
    exit \$exit_status
fi

echo -e "\${GREEN}$software_name execution completed successfully.\${RESET}"
exit 0
EOF

# Make the script executable
chmod +x "$script_path" || error_exit "Failed to make the script executable: $script_path"

# Success message
echo -e "\n\033[0;32mWrapper script created successfully:\033[0m $script_path"
echo -e "You can run it with: \033[0;36m$script_path --help\033[0m to see the usage."
echo -e "Or run it with: \033[0;36m$script_path <command> [args]\033[0m to execute the software."