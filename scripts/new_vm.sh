#!/bin/bash

################################################################################
# New VM
# Description: Deploy and configure a new virtual machine
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jun 08 2025
################################################################################

# Get the hostname
read -p "Insert hostname: " vm

# Select the VM type
read -p "Choose VM type:
1 - Standard VLSI (Rocky 8.10)
2 - Standard VLSI (CentOS 7.9)
3 - AM-Micro {BE} - Contractor
4 - Einfochips {BE} - Contractor
5 - EPP - Ubuntu 22.04
6 - SV - Ubuntu20.04
7 - RHEL - w/o Chef
:" vmtarget

case "$vmtarget" in
    1)
        read -p "Use DHCP or Static IP [Dhcp/Static]?" -n 1 -r
        echo  
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds07 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /DISPLAY-HOSTS
            "
            echo "DONE!"
        else
            read -p "Insert IP address: " ip
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds07 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips '$ip'/16 --cgw 192.168.255.254 --cspec static-ip --dest-folder /DISPLAY-HOSTS
            "
            echo "DONE!"
        fi
    ;;
    2)
        read -p "Use DHCP or Static IP [Dhcp/Static]?" -n 1 -r
        echo  
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsXXX-vnc01-c79 --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /Display-VNC01
            "
            echo "DONE!"
        else
            read -p "Insert IP address: " ip
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsXXX-vnc01-c79 --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips '$ip'/16 --cgw 192.168.255.254 --cspec static-ip --dest-folder /Display-VNC01
            "
            echo "DONE!"
        fi
    ;;


    3)
        read -p "Use DHCP or Static IP [Dhcp/Static]?" -n 1 -r
        echo  
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /DMZ-Internal/AM-Micro
            "
            echo "DONE!"
        else
            read -p "Insert IP address: " ip
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips '$ip'/16 --cgw 192.168.255.254 --cspec static-ip --dest-folder /DMZ-Internal/AM-Micro
               #knife vsphere vm clone $vm --template xsrl8-co-AM-Micro_templ  --datastore ds07 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /DMZ-Internal/AM-Micro
            "
            echo "DONE!"
        fi
    ;;

    4)
        read -p "Use DHCP or Static IP [Dhcp/Static]?" -n 1 -r
        echo  
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /DMZ-Internal/einfochips
            "
            echo "DONE!"
        else
            read -p "Insert IP address: " ip
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --run-list 'role[vlsi-compute]' --tags 'update_autofs_maps' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips '$ip'/16 --cgw 192.168.255.254 --cspec static-ip --dest-folder /DMZ-Internal/einfochips 
	      #knife vsphere vm clone $vm --template xsrl8-co-Einfochip_templ --datastore ds07 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /DMZ-Internal/einfochips
            "
            echo "DONE!"
        fi
    ;;

    5)
        ssh x-infra02 "
            hostname;
            cd /root/chef-repo;
            knife vsphere vm clone $vm --template ubuntu22.tmpl --bootstrap --run-list 'role[ubuntu]' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec eppxxx-vm --dest-folder /EPP-SW
        "
        echo "DONE!"
    ;;
    6)
        ssh x-infra02 "
            hostname;
            cd /root/chef-repo;
            knife vsphere vm clone $vm --template Ubuntu20-template --bootstrap --run-list 'role[ubuntu]' --tags 'update_autofs_maps' --datastore ds05 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec ubuntu-dhcp --dest-folder /SV
        "
        echo "DONE!"
    ;;
    7)
        read -p "Use DHCP or Static IP [Dhcp/Static]?" -n 1 -r
        echo  
        if [[ $REPLY =~ ^[Dd]$ ]]; then
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --datastore ds06 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /Servers
            "
            echo "DONE!"
        else
            read -p "Insert IP address: " ip
            ssh x-infra02 "
                hostname;
                cd /root/chef-repo;
                knife vsphere vm clone $vm --template xsrl8-emp-template --bootstrap --datastore ds06 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips '$ip'/16 --cgw 192.168.255.254 --cspec static-ip --dest-folder /Servers
            "
            echo "DONE!"
        fi
    ;;

    *)
        echo "Invalid option"
        exit 1
    ;;
esac
