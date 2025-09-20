#!/bin/bash

################################################################################
# Add User to AD
# Description: Add a user to Active Directory
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jan 29 2025
################################################################################


read -p "Insert First Name: " fname
	read -p "Insert Last Name: " lname
	read -p "Choose department[SW/VLSI/SYSTEM/BACKEND]:" depart
	read -p "Insert Phone Number(Mendatory): " phone
	read -p "Insert Manager Name: " manager
	read -p "Insert Title(Mendatory): " title
	username=`echo $lname| cut -c1`
	username=`echo $fname$username`
	username=`echo $username |tr [:upper:] [:lower:]`
	pass=`echo $username | cut -c 1 | tr [:lower:] [:upper:]`
	pass="Welcome"$pass"1"
	dn="CN=$fname,OU=Users,OU=exmaple.local,DC=exmaple,DC=local"
	mng="CN=$manager,OU=Users,OU=exmaple.local,DC=exmaple,DC=local"
	sw="CN=sw,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"
	vlsi="CN=vlsi,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"
	rnd="CN=R&D-All,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"
	vpn="CN=VPN_Users,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"

	echo "Username: "$username
	echo "Password: "$pass

	case $depart in
		"SW")
		grp="CN=sw,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"
		;;
		"VLSI")
		grp="CN=vlsi,OU=Groups,OU=exmaple.local,DC=exmaple,DC=local"
		;;
	esac

	ssh -l administrator@amitay x-dc01 "dsadd user "CN=$fname,OU=Users,OU=exmaple.local,DC=exmaple,DC=local" -samid $username -upn $username@amitay.dev -fn $fname -ln $lname -display $fname -disabled no -pwd $pass -dept $depart -email $username@amitay.dev -tel $phone -title $title -memberof $grp $rnd $vpn "
	echo "Account for $fname $lname is ready.
		Username:	$username
		Password:	$pass
		Department:	$depart
		Manager:	
		Phone Number:	$phone" | mail -s "Amitay.dev - New Account Created!" it@amitay.dev
	exit
	;;
