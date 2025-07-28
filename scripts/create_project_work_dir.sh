#!/bin/bash

################################################################################
# Create Project Work Directory
# Description: Create and prepare project work directories
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jun 09 2025
################################################################################


DEBUG_MODE=0

# Function to display help message
show_help() {
    echo "Usage: $0 -user <username> -project <projectname> [-manager <managername>] [-debug]"
    echo ""
    echo "Options:"
    echo "  -user      Username for whom the directory is being created."
    echo "  -project   Project name under /projects/<project>/work/."
    echo "  -copy      (Optional) Copy path from a manager, used if directory needs to be created."
    echo "  -debug     Enable debug mode for troubleshooting."
    echo "  -h         Show this help message."
    exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -user|-u)
            USERNAME="$2"
            shift 2
            ;;
        -project|-p)
            PROJECTNAME="$2"
            shift 2
            ;;
        -copy|-c)
            MANAGER="$2"
            shift 2
            ;;
        -debug|-d)
            DEBUG_MODE=1
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Interactive prompts if required arguments are missing
if [[ -z "$USERNAME" ]]; then
    read -p "Enter username: " USERNAME
fi

if [[ -z "$PROJECTNAME" ]]; then
    read -p "Enter project name: " PROJECTNAME
fi

if [[ -z "$MANAGER" ]]; then
    read -p "Enter manager's name or an employee to copy from(or press Enter to skip): " MANAGER
fi


# Ensure mandatory options are provided
if [[ -z "$USERNAME" || -z "$PROJECTNAME" ]]; then
    echo "Error: Both -user and -project options are required."
    show_help
fi

# Define search path
PROJECT_PATH="/projects/$PROJECTNAME/work"
echo "Define search path PROJECT_PATH is: "$PROJECT_PATH""
echo ""

# Print debug information
if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "[DEBUG] Checking path: $PROJECT_PATH"
fi

# Check if the user directory already exists
EXISTING_DIR=$(find "$PROJECT_PATH" -mindepth 1 -maxdepth 1 -type d -name "$USERNAME" 2>/dev/null)

if [[ -n "$EXISTING_DIR" ]]; then
    echo "User directory '$EXISTING_DIR' already exists."
    exit 0
fi

echo "User directory for '$USERNAME' not found under $PROJECT_PATH."

# Get the server and storage path directly from the auto.master.d file using the manager's name
SERVER_PATH=$(grep -i "$MANAGER" "/etc/auto.master.d/auto.project.$PROJECTNAME.work" | awk '{print $2}' | head -n 1 2>/dev/null)

# If no matching entry is found, prompt for server and project info
if [[ -z "$SERVER_PATH" ]]; then
    echo "Error: Could not find matching server path in '/etc/auto.master.d/auto.project.$PROJECTNAME.work' for manager '$MANAGER'."
    echo "Please provide the server and project information manually."
    
    # Prompt user for server and storage path
    read -p "Enter server (e.g., <SERVER>): " SERVER
    read -p "Enter storage path (e.g., /project_bental_work_gen/users/): " STORAGE_PATH
else
    # Extract server and storage path from the auto.master.d entry
    SERVER=$(echo "$SERVER_PATH" | cut -d':' -f1)
    STORAGE_PATH=$(echo "$SERVER_PATH" | cut -d':' -f2)
    echo "First extraction of STORAGE_PATH: "$STORAGE_PATH""
    echo ""
    
    # Print debug information
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        echo "[DEBUG] Extracted SERVER: $SERVER"
        echo "[DEBUG] Extracted STORAGE_PATH: $STORAGE_PATH"
    fi

    # Remove the manager's name if it appears at the end of the storage path
    STORAGE_PATH=$(echo "$STORAGE_PATH" | sed "s|&||g" | sed "s|/$MANAGER\$||g")

    # Print debug information
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        echo "[DEBUG] Modified STORAGE_PATH (after removing manager's name): $STORAGE_PATH"
    fi
fi

# Ensure STORAGE_PATH does not end with a slash
STORAGE_PATH="${STORAGE_PATH%/}"
echo "My current STORAGE_PATH is "$STORAGE_PATH""
echo ""

# Construct NET_PATH correctly
NET_PATH="/net/$SERVER/$STORAGE_PATH/$USERNAME/"

# Print debug information
if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "[DEBUG] Constructed NET_PATH: $NET_PATH"
fi

# Define the new directory path based on NET_PATH
NEW_DIR="/net/$SERVER/$STORAGE_PATH/$USERNAME"

# Print debug information
if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "[DEBUG] New directory to be created: $NEW_DIR"
fi

# Check if the manager's name is provided, otherwise prompt
if [[ -z "$MANAGER" ]]; then
    read -p "Please enter the manager's name (used to extract volume information): " MANAGER
    if [[ -z "$MANAGER" ]]; then
        echo "Error: Manager's name is required."
        exit 1
    fi
    echo "Using manager: $MANAGER"
fi

# Construct the path to the manager's volume
MANAGER_VOLUME_PATH="/net/$SERVER/$STORAGE_PATH/$MANAGER"
echo "Expected for Manager's path: $MANAGER_VOLUME_PATH"
echo ""

# Print debug information
if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "[DEBUG] Manager's volume path: $MANAGER_VOLUME_PATH"
    echo "[DEBUG] Checking if the manager's volume exists..."
fi

# Check if the manager's volume exists
if [[ ! -d "$MANAGER_VOLUME_PATH" ]]; then
    echo "Error: Manager's volume directory '$MANAGER_VOLUME_PATH' does not exist."
    exit 1
fi

# Create the directory
# Determine if user is an employee or contractor
if [[ "$USERNAME" == c_* ]]; then
        
    # Predefined list of contractor companies
    contractor_companies=("am-micro_grp" "cadence" "einfochips_grp" "proteantecs" "synopsys" "terrain" "vlsi" "epp_sw_c_grp")
    
    echo "User '$USERNAME' is a contractor. Please select the group permission:"
    
    # Display numbered list for selection
    select contractor_company in "${contractor_companies[@]}"; do
        if [[ -n "$contractor_company" ]]; then
            break
        fi
        echo "Invalid selection, please try again."
    done


    home_perm="2755"
    home_group="$contractor_company"
else
    home_group="vlsi"
    home_perm="2750"
fi

mkdir -p "$NEW_DIR"
echo "Changing ownership of $NEW_DIR with '$home_group' group"
chown "$USERNAME:$home_group" "$NEW_DIR"
chmod "$home_perm" "$NEW_DIR"  # Set correct permissions based on user type

echo "User directory created: $NEW_DIR" with '$home_group' group"
exit 0
