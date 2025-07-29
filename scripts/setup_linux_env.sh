#!/bin/bash

################################################################################
# Setup Linux Environment
# Description: Prepare Linux environment 
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jun 12 2025
################################################################################


#########################
# Global Configuration #
#########################
SCRIPT_BASE="/it_apps/scripts"

# Help

# Function to display help message
show_help() {
    echo "Usage: $0 [-user <username>] [-project <projectname>] [-copy] [-debug]"
    echo ""
    echo "Options:"
    echo "  -user      Username for whom the directory is being created."
    echo "  -project   Project name under /projects/<project>/work/."
    echo "  -whoami    enter the username of the person who initiated this setup"
    echo "  -copy      (Optional) Flag indicating if a copy process of autofs maps should be performed."
    echo "  -debug     Enable debug mode for troubleshooting."
    echo "  -h         Show this help message."
    exit 0
}

# Cases

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -user|-u)
            username="$2"
            shift 2
            ;;
        -project|-p)
            projectname="$2"
            shift 2
            ;;
        -whoami)
            it_username="$2"
            shift 2
            ;;
        -copy|-c)
            # Only set if next arg is not another flag
            if [[ -n "$2" && "$2" != -* ]]; then
                copy_enabled="$2"
                shift 2
            else
                copy_enabled=""  # Will trigger prompt later
                shift
            fi
            ;;
        -debug|-d)
            debug_mode=1
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

# Ask only for missing parameters
# Prompt for the initiating user if not already set
if [[ -z "$it_username" ]]; then
    echo ""
    echo "Welcome to setup_linux_env.sh!"
    echo "Please enter the username of the IT personnel who initiated this setup (e.g., aviela):"
    echo ""
    read -rp "Username: " it_username

    # Validate non-empty input
    if [[ -z "$it_username" ]]; then
        echo "Error: Username cannot be empty. Exiting."
        exit 1
    fi
fi

if [[ -z "$username" ]]; then
    echo ""
    read -p "insert username to create: " username
fi

if [[ -z "$projectname" ]]; then
    read -p "insert project name: " projectname    
fi

if [[ -z "$copy_enabled" ]]; then
    read -p "insert user to copy autofs maps from: " copy_enabled
fi

# Convert all inputs to lowercase
username=$(echo "$username" | tr '[:upper:]' '[:lower:]')
projectname=$(echo "$projectname" | tr '[:upper:]' '[:lower:]')
copy_enabled=$(echo "$copy_enabled" | tr '[:upper:]' '[:lower:]')

##################
# Home Settings #
##################

# Determine if user is an employee or contractor
if [[ "$username" == c_* ]]; then
    home_group="domain contractors"
    
    # Predefined list of contractor companies
    contractor_companies=("am-micro" "AmMicro" "cadence" "einfochips" "proteantecs" "softpower" "synopsys" "terrain" "Sii" "Geminus")
    
    echo "User '$username' is a contractor. Please select the company:"
    
    # Display numbered list for selection
    select contractor_company in "${contractor_companies[@]}"; do
        if [[ -n "$contractor_company" ]]; then
            break
        fi
        echo "Invalid selection, please try again."
    done

    # Default base directory
    base_dir="/net/<SERVER>/vol001/home/contractors/$contractor_company"

    # Override base directory for special cases
    case "$contractor_company" in
        Sii)
            base_dir="/net/<IP-Address>/vol_sii_248/home/"
            ;;
        Geminus)
            base_dir="/net/<IP-Address>/geminus_248/home"
            ;;
    esac

    home_dir="$base_dir/$username"
    home_perm="2755"
else
    home_group="vlsi"
    home_dir="/net/<SERVER>/vol001/home/$username"
    home_perm="2750"
fi

# Check if home directory exists
echo "Checking if home directory for $username exists at $home_dir..."
if [[ ! -d "$home_dir" ]]; then
    echo "Home directory does not exist. Creating home directory for $username..."
    sudo mkdir -p "$home_dir"
    
    echo "Changing ownership of $home_dir to $home_group"
    chown "$username:$home_group" "$home_dir"
    chmod "$home_perm" "$home_dir"  # Set correct permissions based on user type

    echo "Home directory for $username created at $home_dir with group '$home_group'."
    echo "Permissions set to $home_perm."
else
    echo "Home directory already exists for $username, in path $home_dir"
fi

######################
# Project settings #
######################
# Determine if user is a contractor
if [[ "$username" == c_* ]]; then
    contractor_companies=("am-micro_grp" "cadence" "einfochips_grp" "proteantecs" "synopsys" "terrain" "vlsi" "epp_sw_c_grp" "geminus_grp")

    echo "User '$username' is a contractor. Please select the group permission:"
    select contractor_company in "${contractor_companies[@]}"; do
        if [[ -n "$contractor_company" ]]; then
            break
        fi
        echo "Invalid selection, please try again."
    done

    work_perm="2755"  # setgid bit for contractors
    work_group="$contractor_company"
else
    work_group="vlsi"
    work_perm="2750"  # setgid bit for employees
fi


# Define work directory path
work_dir="/projects/$projectname/work/$username"
echo "Path of work_dir is: "$work_dir""

# **Handling for arava, arad, bareket projects (Use /mnt)**
if [[ "$projectname" == "arava" || "$projectname" == "arad" || "$projectname" == "bareket" ]]; then
    echo "Processing project: $projectname"

    # Assign volume based on username's first letter
    case "$(echo "$username" | cut -c1)" in
        [a-d]) vol="vol005" ;;
        [e-h]) vol="vol006" ;;
        [i-l]) vol="vol007" ;;
        [m-p]) vol="vol008" ;;
        [q-t]) vol="vol009" ;;
        [u-z]) vol="vol010" ;;
        *) echo "Invalid username"; exit 1 ;;
    esac

    mnt_path="/mnt/$vol/$username"
    filer_path="/net/<SERVER>/$vol/$username"

    # Ensure Qtree exists
    echo "Checking Qtree for $username..."
    ls /mnt/$vol/$username/ > /dev/null
    if [ $? != 0 ]; then
      echo "Creating Qtree..."
      ssh svmadmin1@<IP-Address> "qtree create $vol -vserver <SERVER> -qtree $username" > /dev/null
    fi

    # Create work/home directories and set permissions
    echo "setting up work and home directories for project $projectname..."
    chown "$username:$work_group" "$filer_path"
    mkdir -p "$filer_path/$projectname/work" "$filer_path/$projectname/home"
    chown -R "$username:$work_group" "$mnt_path/$projectname"
    chmod -R "$work_perm" "$filer_path" # with a sticky bit

    # Verify ownership and permissions
    owner_check=$(stat -c "%U:%G" "$filer_path")
    perm_check=$(stat -c "%a" "$filer_path")

if [[ "$owner_check" == "$username:vlsi" && "$perm_check" == "2750" ]]; then
    echo "Ownership and permissions successfully set on $filer_path"
else
    echo "Error: Ownership or permissions not set correctly on $filer_path"
    echo "Current owner: $owner_check, Expected: $username:vlsi"
    echo "Current permissions: $perm_check, Expected: 2750"
    echo "Please run the IT-Services a second time for fixing the permissions"
    exit 1
fi
    
    # Create symlinks in /projects
    ln -s "$mnt_path/$projectname/home" "/projects/$projectname/home/$username"
    ln -s "$mnt_path/$projectname/work" "/projects/$projectname/work/$username"

    echo "project $projectname work/home directories set up for $username."
    # exit 0
fi


# **Handling for Alon**
if [[ "$projectname" == "alon" ]]; then
    echo "Processing project: $projectname"

    alon_path="/net/<SERVER>/project_alon/work"
    user_dir="$alon_path/$username"

    mkdir -p "$user_dir"

    echo "Setting group ownership to '$work_group' for $user_dir"
    if chown -R "$username:$work_group" $user_dir; then
        echo "Ownership updated successfully."
        echo ""
    else
        echo "Failed to update ownership." >&2
    fi

    echo "Setting permissions to '$work_perm' for $user_dir"
    if chmod -R "$work_perm" "$user_dir"; then
        echo "Permissions updated successfully."
        echo ""
    else
        echo "Failed to update permissions." >&2
    fi

    echo "Directory created at $user_dir for '$username'"
    echo ""
fi

# **Handling for arbel, bental, eshkol projects (Use /projects and call external script)**
if [[ "$projectname" == "arbel" || "$projectname" == "bental" || "$projectname" == "eshkol" ]]; then

# Define the work directory path before checking
work_dir="/projects/$projectname/work/$username"
echo "Expected work_dir path is $work_dir"
echo "Run $projectname debug_mode"
    if [[ ! -d "$work_dir" ]]; then
        echo "user directory for '$username' not found under /projects/$projectname/work."
        echo "executing external script "create_project_work_dir.sh" to create the work directory..."
        sh "$SCRIPT_BASE/create_project_work_dir.sh" -user "$username" -project "$projectname" -copy "$copy_enabled"
        echo ""
        echo "Run external script "update_autofs_maps""
        # sh /home/aviela/it_services/scripts/update_autofs_maps.sh -user "$username" -project "$projectname" -copy "$copy_enabled" -whoami "$it_username"
        sh "$SCRIPT_BASE/update_autofs_maps.sh" -user "$username" -project "$projectname" -copy "$copy_enabled" -whoami "$it_username"
    fi

    echo ""
    echo "Continue with the procceed running back from "setup_linux_env" script"
    home_proj="/projects/$projectname/home/$username"
    echo "Debug: Expected home_project path is $home_proj"
    mkdir $home_proj
    chown $username:$work_group $home_proj
    chmod "$work_perm" $home_proj

    echo "Setup complete for user: $username in project: $projectname."
fi

# **Only show warning if it is NOT a known project**
if [[ "$projectname" != "arava" && "$projectname" != "arad" && "$projectname" != "bareket" && \
      "$projectname" != "alon" && \
      "$projectname" != "arbel" && "$projectname" != "bental" && "$projectname" != "eshkol" ]]; then
    echo ""
    echo "*** Attention: Project '$projectname' is not a standard supported project, please create a work directory manually. ***"
    echo ""
fi

# **Ensure project home directory creation**
home_proj="/projects/$projectname/home/$username"
if [[ ! -d "$home_proj" ]]; then
    echo "Creating project home directory at $home_proj"
    mkdir -p "$home_proj"
    chown "$username:$work_group" "$home_proj"
    chmod "$work_perm" "$home_proj"
fi

#####################
# VM Configuration #
#####################

# Prompt to confirm creating a personal VM
read -t 80 -p "Would you like to create a personal-vnc VM for $username? [y/n]: " confirmation


if [[ "$confirmation" =~ ^[yY]$ ]]; then
  
  # Construct VM name
  vm_name="xs${username}-vnc01"
  echo "Checking if VM $vm_name exists for $username ..."

  # Check if node exists in Chef (remote server)
  vm_exist_check=$(ssh x-infra02 "cd /root/chef-repo; /opt/chef-workstation/bin/knife node list 2>/dev/null | grep $vm_name")

  if [ -z "$vm_exist_check" ]; then
    # VM doesn't exist, so create one
    echo "VM $vm_name does not exist. Setting up personal Rocky Linux 8.10 VM for $username ..."

    ssh x-infra02 "
        hostname
        cd /root/chef-repo && \
        /opt/chef-workstation/bin/knife vsphere vm clone $vm_name \
            --template xsrl8-emp-template \
            --bootstrap --run-list 'role[vlsi-compute]' \
            --datastore ds07 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp \
            --tags 'update_autofs_maps' \
            --cspec personal-vnc --dest-folder /Display-VNC01
    "

    # Check if the SSH/knife command was successful
    if [ $? -ne 0 ]; then
        echo "Error during VM setup for '$username'."
    else
        echo "VM setup for user '$username' complete."
    fi
  else
    # VM name was found
    echo "VM $vm_name already exists."
  fi
else
  echo "Operation cancelled for VM creation."
fi

## Prompt to run Chef client on all VLSI servers
echo ""
echo "*** Check of Jenkins job complete before you continue update the autofs maps ***"
echo ""

# Path to the script to check
CHECK_SCRIPT="$SCRIPT_BASE/Jenkins_status.sh"

while true; do
    echo ""
    echo "Waiting for 2 minutes before checking Jenkins status..."
    sleep 120

    output=$("$CHECK_SCRIPT")

    if [[ "$output" == "Build succeeded" ]]; then
        echo ""
        echo "✅ Jenkins check passed: $output"

        # Ask user if they want to proceed
        read -t 300 -p "Would you like to proceed with the rest of the script? [y/n]: " proceed
        case "$proceed" in
            [Yy]*)
                break
                ;;
            *)
                echo "You chose not to proceed. Exiting."
                exit 0
                ;;
        esac

    else
        echo ""
        echo "⏳ Jenkins check returned: $output"
        read -t 300 -p "Do you want to wait another 2 minutes and retry? [y/n]: " retry
        case "$retry" in
            [Yy]*) continue ;;
            *) echo "Exiting as per user request."; exit 1 ;;
        esac
    fi
done

# Loop until success or user declines to wait further
while true; do
    echo "Waiting for 2 minutes before checking..."
    sleep 120

    # Capture output of the script
    output=$("$CHECK_SCRIPT")

    # If the script returns "Build succeeded", continue with main logic
    if [[ "$output" == "Build succeeded" ]]; then
    # if [[ "$output" == "SUCCESS" ]]; then
        echo "Check passed: SUCCESS"
        break
    else
        echo "Check script returned: $output"
        read -t 500 -p "Do you want to wait another 2 minutes? [y/n]: " answer
        case "$answer" in
            [Yy]*) continue ;;
            *) echo "Exiting as per user request."; exit 1 ;;
        esac
    fi
done

# Continue main script logic here
echo ""
read -t 200 -p "Would you like to update autofs maps? [y/n]: " confirmation


if [[ "$confirmation" =~ ^[yY]$ ]]; then
    echo "Running external script 'upload_cookbook.sh'"
    echo ""
    sh "$SCRIPT_BASE/upload_cookbook.sh "
    echo ""
    echo "Update update_autofs_maps"
    sh "$SCRIPT_BASE/run_full_chef_client.sh" -role tags:update_autofs_maps ; exit  
else
  echo "Autofs maps update skipped."
fi

# done
