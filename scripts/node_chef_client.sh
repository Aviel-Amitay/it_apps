#!/bin/bash

################################################################################
# Node Chef Client
# Description: Manage Chef client runs on nodes
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 27 2025
################################################################################

# Define the log directory for output and error logs (on x-infra02)
log_dir="/tools/IT/inventory/chef/logs/"
timestamp=$(date +"%Y-%m-%d_%H%M%S")

# Prompt to confirm running chef-client on all nodes
read -p "Enter VM name for running chef-client: " vmname

# Optional: remove offending host key line from known_hosts if error is detected
host_key_file="/root/.ssh/known_hosts"
tmp_error=$(mktemp)

# Test SSH connection and capture key error line
ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR $vmname "exit" 2> "$tmp_error"

if grep -q "Offending ECDSA key" "$tmp_error"; then
    line_number=$(grep "Offending ECDSA key" "$tmp_error" | sed -E 's/.*known_hosts:([0-9]+).*/\1/')
    if [[ "$line_number" =~ ^[0-9]+$ ]]; then
        echo "⚠️  Removing bad host key from $host_key_file (line $line_number)"
        sed -i "${line_number}d" "$host_key_file"
    fi
fi

rm -f "$tmp_error"

ssh x-infra02 "
  cd /root/chef-repo
  cmd=\"ssh $vmname '/bin/chef-client' | tee -a $log_dir/${timestamp}_${vmname}.log\"
  echo \"Running: \$cmd\"
  eval \"\$cmd\"
"
