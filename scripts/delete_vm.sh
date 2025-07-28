#!/bin/bash

################################################################################
# Delete VM
# Description: Delete virtual machines from the infrastructure
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jan 29 2025
################################################################################


# Prompt the user for the VM name
read -p "Insert VM name: " vmn

# Domain Controller and DNS Server Details
username="administrator@amitay"
domain="amitay.dev"
server="x-dc02"
domain_info="$username"

# Delete AD object through the Domain Controller
echo "Delete AD object and DNS record through the Domain Controller"
echo ""

# Step 1: Check and Delete the AD Computer Object
ssh -l "$domain_info" "$server" "cmd.exe /c \"dsquery computer -name $vmn\"" | while read -r dn; do
    if [[ -n "$dn" ]]; then
        echo "Found computer: $dn"

        # Execute the deletion command
        ssh -l "$domain_info" "$server" "cmd.exe /c \"dsrm $dn -noprompt\""
        
        # Check if deletion was successful
        if [[ $? -eq 0 ]]; then
            echo "Computer $dn deleted successfully."
        else
            echo "Failed to delete $dn."
        fi
    else
        echo "No object found for \"$vmn\""
    fi
done

# Step 2: Check and Delete DNS Record
echo "Checking for DNS record of '$vmn' on $domain_info..."
dns_check=$(nslookup "$vmn" | grep 'Name:')

if [[ -n "$dns_check" ]]; then
    echo "DNS record found for '$vmn'. Attempting to delete..."
    
    # Run the deletion command for the DNS record
    ssh -l "$domain_info" "$server" "cmd.exe /c \"dnscmd $domain /recorddelete $domain $vmn A /f\""

    # Check if deletion was successful
    if [[ $? -eq 0 ]]; then
        echo "DNS record for '$vmn' deleted successfully."
    else
        echo "Failed to delete DNS record for '$vmn'."
    fi
else
    echo "No DNS record found for '$vmn'."
fi

echo ""


# SSH to the remote machine and execute the delete command
ssh x-infra02 "
    cd /root/chef-repo && \
    echo "Delete VM from the vCenter"
    echo ""
    /opt/chef-workstation/bin/knife vsphere vm delete $vmn -P
    echo ""
    echo 'DONE'
"
