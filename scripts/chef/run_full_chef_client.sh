#!/bin/bash

################################################################################
# Run Full Chef Client
# Description: Run full Chef client process with options
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 27 2025
################################################################################


#Global_Configuration:
host=x-infra02
pwd=/root/chef-repo/
command='/opt/chef-workstation/bin/knife ssh'
log_dir='/tools/IT/inventory/chef/logs'

#############################################
echo ""
echo "Welcome to Chef Client wizard. Choose on which nodes (VM/Servers) you want to run Chef Client base on role"
echo ""

# Default values
role=""
print_flag=1
verbose=1

# Map numbers to actual role names
declare -A role_map
role_map=(
  [1]="vlsi-compute"
  [2]="vlsi-display"
  [3]="ubuntu"
  [4]="zebu"
  [5]="ipaddress:192.168.1.*"
  [6]="tags:update_autofs_maps"
  [7]="all"
)


# CLI flags option for automate
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -role)
      role="$2"
      shift 2
      ;;
    --print)
      print_flag=1
      shift
      ;;
    -v|--verbose)
      verbose=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 -role role [--print] [-v]"
      exit 0
      ;;
    *)
      echo "Unknown parameter passed: $1"
      echo "Switching to interactive mode..."
      role=""
      shift
      ;;
  esac
done

# Interactive prompts if required arguments are missing
if [[ -z "$role" ]]; then
    echo "1 - vlsi-compute"
    echo "2 - vlsi-display"
    echo "3 - ubuntu"
    echo "4 - zebu"
    echo "5 - infrastructure apps"
    echo "6 - update autofs maps main"
    echo "7 - all"
    read -p "Choose role name or number: " role
fi

# Convert number to role name if needed
if [[ ${role_map[$role]+_} ]]; then
  resolved_role="${role_map[$role]}"
else
  resolved_role="$role"
fi

# Translet the name / Number to the match role
if [[ "$resolved_role" == "all" ]]; then
  search="name:*"
elif [[ "$resolved_role" == ipaddress:* || "$resolved_role" == tags:* ]]; then
  search="$resolved_role"
else
  search="role:$resolved_role"
fi

# Build the actual knife command
timestamp=$(date +"%Y-%m-%d_%H%M%S")
log_file="$log_dir/${resolved_role//[:*]/_}_$timestamp.log"

if [[ "$resolved_role" == "tags:update_autofs_maps" ]]; then
  chef_cmd="chef-client -o autofs::main-autofs"
else
  chef_cmd="chef-client"
fi

cmd="ssh $host \"hostname; cd $pwd; $command '$search' '$chef_cmd' -y\""

# Print the command if --print was passed
if [[ "$print_flag" -eq 1 ]]; then
  echo " Command to run:"
  echo "$cmd"
  echo ""
fi

# Run it
echo " Running Chef Client for: $resolved_role"
echo " Output logging to: $log_file"
eval "$cmd" | tee "$log_file"
