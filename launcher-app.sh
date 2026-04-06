#!/bin/bash

################################################################################
# Launcher-app
# Description: A centralized launcher for IT services scripts, 
#              providing a user-friendly menu to execute various tasks related to user management, 
#              environment setup, machine operations, AWS management, and backup automation.
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay/it_apps
# Modified: Apr 06 2026
################################################################################

# set -x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

if [[ ! -d "$SCRIPT_DIR" ]]; then
  echo "❌ ERROR: SCRIPT_DIR directory '$SCRIPT_DIR' not found!"
  exit 1
fi

LINUX_SCRIPT_DIR="$SCRIPT_DIR/linux_env"
AWS_SCRIPT_DIR="$SCRIPT_DIR/aws"
CHEF_SCRIPT_DIR="$SCRIPT_DIR/chef"
LOG_FILE="$ROOT_DIR/launcher.log"

# Prompt for the initiating user if not already set
if [[ -z "$it_username" ]]; then
    echo ""
    echo "Welcome to the IT Services Launcher!"
    echo "Please enter the username of the IT personnel who initiated this setup (e.g., aviela):"
    echo ""
    read -rp "Username: " it_username
fi

# Define categorized menu items
USER_ACTIONS=(
  "delete_vm.sh:Delete a VM"
  "setup_linux_env.sh:Setup a Linux environment for user"
  "initial_process.sh:Setup local env for user"
  "add_user_to_ad.sh:Add a user to AD"
)

ENV_ACTIONS=(
  "edit_cookbook_metadata.sh:Edit a cookbook's metadata.rb file"
  "upload_cookbook.sh:Upload a cookbook"
  "edit_chef_node.sh:Edit a chef node"
  "check_licenses_servers.sh:Check license servers status"
  "sge_actions.sh:SGE actions"
  "speed_test.sh:Run Speed test"
  "export_active_users.sh:Export AD 'Amitay' users"
)

MACHINE_ACTIONS=(
  "bootstrap_machine.sh:Bootstrap a new machine"
  "run_full_chef_client.sh:Full chef-client on specific role"
  "run_autofs_chef_client.sh:Chef-client for autofs maps [VLSI]"
  "compare_rpms.sh:Compare RPMs between hosts"
  "new_vm.sh:Create a new VM"
)

AWS_ACTIONS=(
  "build_multi_vpc.sh:Build a multi-VPC environment in AWS"
  "manage_aws_security.sh:Create and manage AWS SSH and security groups"
  "manage_ec2_instance.sh:Create a new EC2 instance in AWS"
)

BACKUP_ACTIONS=(
  "automate_external_backup.sh:Initial monthly disk backup"
)

show_main_menu() {
  echo ""
  echo "========== IT Services Launcher =========="
  echo "1 - User Actions"
  echo "2 - Environment Actions"
  echo "3 - Machine Actions"
  echo "4 - AWS Actions"
  echo "5 - Backup Actions"
  echo "q - Quit"
  echo "=========================================="
}

run_script_menu() {
  local category_name=$1[@]
  local category=("${!category_name}")

  echo ""
  echo "Select a script to run:"
  for i in "${!category[@]}"; do
    echo "$((i + 1)) - ${category[i]#*:}"
  done
  echo "b - Back"

  while true; do
    read -rp "Choice [1-${#category[@]} or b]: " sub_choice
    if [[ "$sub_choice" == "b" ]]; then
      return
    elif [[ "$sub_choice" =~ ^[0-9]+$ && "$sub_choice" -ge 1 && "$sub_choice" -le ${#category[@]} ]]; then
      index=$((sub_choice - 1))
      script_file="${category[index]%%:*}"
      description="${category[index]#*:}"

      # Find the script path
      if [[ -f "$SCRIPT_DIR/$script_file" ]]; then
        full_path="$SCRIPT_DIR/$script_file"
      elif [[ -f "$LINUX_SCRIPT_DIR/$script_file" ]]; then
        full_path="$LINUX_SCRIPT_DIR/$script_file"
      elif [[ -f "$AWS_SCRIPT_DIR/$script_file" ]]; then
        full_path="$AWS_SCRIPT_DIR/$script_file"
      elif [[ -f "$CHEF_SCRIPT_DIR/$script_file" ]]; then
        full_path="$CHEF_SCRIPT_DIR/$script_file"
      else
        echo "Error: $script_file not found."
        return
      fi

      echo ""
      echo ">>> [$it_username] is running: $description"
      echo "------------------------------------------"
      echo "$(date '+%Y-%m-%d %H:%M:%S') | $it_username | $script_file | $description" >> "$LOG_FILE"

      if [[ "$script_file" == *.py ]]; then
        python3 "$full_path"
      elif [[ -x "$full_path" ]]; then
        "$full_path"
      else
        bash "$full_path"
      fi

      echo "------------------------------------------"
      return
    else
      echo "Invalid input. Try again."
    fi
  done
}

# Main loop
while true; do
  show_main_menu
  read -rp "Choose a category [1–5 or q]: " choice
  case "$choice" in
    1) run_script_menu USER_ACTIONS ;;
    2) run_script_menu ENV_ACTIONS ;;
    3) run_script_menu MACHINE_ACTIONS ;;
    4) run_script_menu AWS_ACTIONS ;;
    5) run_script_menu BACKUP_ACTIONS ;;
    q) echo "Goodbye!"; exit 0 ;;
    *) echo "Invalid option. Try again." ;;
  esac
done
