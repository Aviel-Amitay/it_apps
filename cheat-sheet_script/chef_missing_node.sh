#!/bin/bash

################################################################################
# Chef Missing Node
# Description: Automation script for 'chef_missing_node.sh'
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay/it_apps
# Modified: Apr 06 2026
################################################################################


set -euo pipefail

cat <<'EOF'

###########################################
check_for_missing_chef_node.sh

Purpose:
1. Connect to vCenter through pwsh / PowerCLI
2. Pull VM list
3. Filter only relevant VM names
4. Exclude unwanted patterns
5. Compare vCenter VM list against Chef node list
6. Email only VMs that exist in vCenter but not in Chef
###########################################


Note: This script assumes you have PowerCLI installed and configured on the system where it's run.
For secure password handling, we recommend encrypting the vCenter password using OpenSSL and storing it in a file with strict permissions.

###########################################
# Create encrypted password (run once, then comment out):
echo -n 'your-password' | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -a -salt -pass pass:StrongKey > ~/vcenter.enc

# 🔓 You can test and decrypt it with (must use same flags):
VCENTER_PASS=$(openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -a -d -salt -in ~/vcenter.enc -pass pass:StrongKey)

EOF

###############
# CONFIG
###############
VCENTER_HOST="XXXX"
VCENTER_USER="administrator@vsphere.local"

ENC_FILE="$HOME/secret/.vcenter.enc"
ENC_KEY="StrongKey"

REFERENCE_FILE="/root/current_rhel_display_role_node_list.txt"
FINAL_OUTPUT_FILE="/tmp/vCenter_vm_list.txt"
DIFF_REPORT="/tmp/vm_diff_report.txt"

EMAIL_TO="your@email.com"

###############
# PRECHECKS
###############
if [[ ! -r "$ENC_FILE" ]]; then
    echo "ERROR: Cannot read encrypted password file: $ENC_FILE"
    ls -l "$ENC_FILE" 2>/dev/null || true
    exit 1
fi

if [[ ! -f "$REFERENCE_FILE" ]]; then
    echo "ERROR: Reference file not found: $REFERENCE_FILE"
    exit 1
fi

###############
# DECRYPT PASSWORD
###############
VCENTER_PASS="$(
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -a -d \
    -in "$ENC_FILE" \
    -pass pass:"$ENC_KEY"
)"

###############
# GET VM LIST FROM VCENTER
###############
pwsh -NoProfile -Command "
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP \$false -Confirm:\$false | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:\$false | Out-Null

\$pw   = ConvertTo-SecureString '$VCENTER_PASS' -AsPlainText -Force
\$cred = New-Object System.Management.Automation.PSCredential('$VCENTER_USER', \$pw)

Connect-VIServer -Force -Server '$VCENTER_HOST' -Credential \$cred | Out-Null

Get-VM |
Where-Object {
    (
        \$_.Name -match 'web|vnc|dsrv'
    ) -and
    (
        \$_.Name -notmatch 'ctx|2d'
    )
} |
Select-Object -ExpandProperty Name |
Sort-Object |
Set-Content -Path '$FINAL_OUTPUT_FILE'

Disconnect-VIServer -Server '$VCENTER_HOST' -Confirm:\$false | Out-Null
exit
"

###############
# CLEAN FILES BEFORE COMPARE
###############
clean_file() {
    local input_file="$1"

    sed '/^Name$/d;/^----$/d' "$input_file" \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -vE '^[[:space:]]*$' \
    | sort -u
}

clean_file "$REFERENCE_FILE" > /tmp/chef_nodes_clean.txt
clean_file "$FINAL_OUTPUT_FILE" > /tmp/vcenter_nodes_clean.txt

###############
# FIND VMs IN VCENTER BUT NOT IN CHEF
###############
diff \
  --old-line-format='' \
  --new-line-format='%L' \
  --unchanged-line-format='' \
  <(sort /tmp/chef_nodes_clean.txt) \
  <(sort /tmp/vcenter_nodes_clean.txt) \
  > "$DIFF_REPORT"

###############
# SEND EMAIL IF DIFF EXISTS
###############
if [[ -s "$DIFF_REPORT" ]]; then
    {
        echo "*** Node VMs detected in vCenter that are not managed by Chef ***"
        echo ""
        echo "vCenter-only nodes:"
        echo "-------------------"
        cat "$DIFF_REPORT"
        echo ""
        echo "Reference file : $REFERENCE_FILE"
        echo "vCenter file   : $FINAL_OUTPUT_FILE"
        echo "Diff file      : $DIFF_REPORT"
    } | mail -s "Missing Chef integration on $VCENTER_HOST" "$EMAIL_TO"
else
    echo "No differences found, email not sent."
fi

###############
# DEBUG OUTPUT
###############
echo ""
echo "Reference file : $REFERENCE_FILE"
echo "vCenter file   : $FINAL_OUTPUT_FILE"
echo "Diff file      : $DIFF_REPORT"