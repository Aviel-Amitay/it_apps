#!/bin/bash

################################################################################
# Edit Chef Node
# Description: Edit Chef node configurations
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jan 29 2025
################################################################################

echo " "

read -p "Insert node name: " noden
	   ssh -t x-infra02 "hostname; cd /root/chef-repo/; /opt/chef-workstation/bin/knife node edit $noden" 
	   exit
	;;
