#!/bin/bash
################################################################################
# Bootstrap Machine
# Description: Register new node hosts to the Chef system
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 27 2025
################################################################################

echo ""
echo "*** This script is for the initial registration of a node with Chef. ***"
echo "*** If the host is already registered, please choose: 'Run Chef-client for specific host' ***"
echo ""


bootstrap_machine() {
    local machine=$1
    local run_list=$2
    if nslookup "$machine"; then
        echo "Bootstrapping $machine now ..."  
            if [ -z "$run_list" ]; then
                cmd="ssh x-infra02 \"hostname; cd /root/chef-repo/; /opt/chef-workstation/bin/knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never\" -y"
            else
                cmd="ssh x-infra02 \"hostname; cd /root/chef-repo/; /opt/chef-workstation/bin/knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never --run-list '$run_list'\" -y"
            fi       
            echo "Executing command: $cmd"      
            eval "$cmd"      
        echo "DONE"
        exit 0
    else
        echo "Cannot find hostname $machine, exiting..."
        exit 1
    fi
}


bootstrap_machine_with_autofs_tags() {
    local machine=$1
    local run_list=$2
    if nslookup "$machine"; then
        hostname
            echo "Bootstrapping with role vlsi-display on $machine now ..."      
            echo ""
            cmd="ssh x-infra02 \"hostname; cd /root/chef-repo/; /opt/chef-workstation/bin/knife bootstrap --run-list '$run_list'\" --tags 'update_autofs_maps' $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never -y"
            echo "Executing command: $cmd"      
            eval "$cmd"      
        echo "DONE"
        exit 0
    else
        echo "Cannot find hostname $machine, exiting..."
        exit 1
    fi
}

read -p "Insert hostname: " machine
echo "What role to use:
1) vlsi-compute
2) vlsi-display
3) ubuntu
4) zebu
5) no config, only bootstrap"
read -p ": " role_type

case "$role_type" in
    1) bootstrap_machine                  "$machine" "role[vlsi-compute]" ;;
    2) bootstrap_machine_with_autofs_tags "$machine" "role[vlsi-display]" ;;
    3) bootstrap_machine                  "$machine" "role[ubuntu]" ;;
    4) bootstrap_machine_with_autofs_tags "$machine" "role[zebu]" ;;
    5) bootstrap_machine                  "$machine" ;;
    *)
        echo "Invalid option selected!"
        exit 1
        ;;
esac
