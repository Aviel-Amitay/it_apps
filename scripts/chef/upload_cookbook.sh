#!/bin/bash

################################################################################
# Upload Cookbook
# Description: Upload Chef cookbooks to the Chef server
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 16 2025
################################################################################


ssh x-infra02 "
        hostname;
        echo ""
        cd /root/chef-repo/;
        echo "Update Chef git repository to the latest"
        git pull origin master
        echo ""
        echo "Chef repo downloaded successfully"
        echo ""
    "

read -p "Choose cookbook to upload:
    1] SSHD
    2] Auth 
    3] sudoers
    4] packages 
    5] autofs
    6] sys_config
    7] zebu
    8] ubuntu
    9] display
    10] ALL - Except of zebu and ubuntu
    Enter option (1-10): " choice

if [[ $choice == 10 ]]; then
    read -p "Are you sure you want to upload ALL cookbooks? (yes/no): " confirm
    if [[ $confirm == "yes" ]]; then
        ssh x-infra02 "
            hostname;
            echo ""
            cd /root/chef-repo/;
            echo ""
            echo "Running upload cookbook: "$cookbook""
            /opt/chef-workstation/bin/knife cookbook upload sshd;
            /opt/chef-workstation/bin/knife cookbook upload auth;
            /opt/chef-workstation/bin/knife cookbook upload sudoers;
            /opt/chef-workstation/bin/knife cookbook upload packages;
            /opt/chef-workstation/bin/knife cookbook upload autofs;
            /opt/chef-workstation/bin/knife cookbook upload sys_config;
            /opt/chef-workstation/bin/knife cookbook upload display;
        "
        echo "All cookbooks uploaded."
    else
        echo "Operation cancelled."
    fi
else
    case $choice in
        1) cookbook="sshd" ;;
        2) cookbook="auth" ;;
        3) cookbook="sudoers" ;;
        4) cookbook="packages" ;;
        5) cookbook="autofs" ;;
        6) cookbook="sys_config" ;;
        7) cookbook="zebu" ;;
        8) cookbook="ubuntu" ;;
        9) cookbook="display" ;;
        *) echo "Invalid option" && exit 1 ;;
    esac
    ssh x-infra02 "
        hostname;
        echo ""
        cd /root/chef-repo/;
        echo ""
        echo "Running upload cookbook: "$cookbook""
        /opt/chef-workstation/bin/knife cookbook upload $cookbook
    "
    echo "Cookbook '$cookbook' uploaded."
fi
