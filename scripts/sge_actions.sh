#!/bin/bash

read -p "SGE Menu: Please choose action from the list: 
		1  - Show all Jobs
		2  - Add submit host
		3  - Edit Queue
		4  - Show total slots usage
		5  - Show sum of all slots
	:" subtarget

	case "$subtarget" in
		1) qstat -u "*"
		exit
		;;
		2) read -p "Insert hostname: " hostn
		qconf -as $hostn
		exit
		;;
		3) read -p "Insert Queue Name: " queuen
		qconf -mq $queuen
		exit
		;;
		4) qstat -u "*" | grep -w 'r' | awk -F ' ' '{sum += $9} END {print sum}' ; exit
		;;
		5) qstat -f | grep 'backend\|all.q' | awk '{print $3}' | awk -F '/' '{sum += $3} END {print sum}'
		;;
		[a-z][A-Z]) echo "Please insert valid option"
		;;
	esac
	;;