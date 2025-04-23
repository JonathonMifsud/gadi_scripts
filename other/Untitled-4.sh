#!/bin/bash

# =============================================================================
# Singularity Wrapper Script Generator
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

script_path="$bin_dir/run_${software_name}.sh"

# =============================================================================
# CREATE WRAPPER SCRIPT
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
    echo -e "\${BOLD}Usage:\${RESET} \$0 [--bind_extra_paths <path>] [-- <software arguments>]"
    echo ""
    echo -e "\${BOLD}Description:\${RESET}"
    echo -e "This wrapper runs \${CYAN}$software_name\${RESET} inside its Singularity container."
    echo "It ensures the correct version is used (from your config file) and allows extra bind paths."
    echo ""
    echo -e "\${BOLD}Wrapper Options:\${RESET}"
    echo -e "  \${GREEN}--bind_extra_paths <path>\${RESET}   Bind additional host paths (e.g. /scratch:/mnt/scratch)"
    echo -e "  \${GREEN}-h, --help\${RESET}                  Show this wrapper help and then internal tool help"
    echo ""
    echo -e "\${BOLD}Note:\${RESET} If you use \${GREEN}-h\${RESET} or \${GREEN}--help\${RESET}, the wrapper help will be shown first,"
    echo -e "then the internal help for \${CYAN}$software_name\${RESET} will automatically follow."
    echo ""
    echo -e "\${BOLD}Passing arguments to \${CYAN}$software_name\${RESET}:\${RESET}"
    echo "Use -- to separate wrapper options from the tool's arguments."
    echo "Everything after -- is passed directly to the internal tool."
    echo ""
    echo -e "\${BOLD}Examples:\${RESET}"
    echo -e "  \${CYAN}\$0 -h\${RESET}"
    echo "      → Shows this wrapper's help and then $software_name's help"
    echo ""
    echo -e "  \${CYAN}\$0 -- --version\${RESET}"
    echo "      → Runs '$software_name --version' inside the container, you can replace --version with any argument from $software_name"
    echo ""
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
    singularity exec --bind "\$default_bind_paths" "\$image" $software_name --help
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

# Execute the software inside the Singularity container
singularity exec --bind "\$bind_paths" "\$image" $software_name "\$@"

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

chmod +x "$script_path"