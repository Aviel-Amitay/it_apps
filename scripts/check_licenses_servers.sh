#!/bin/bash

################################################################################
# Check Licenses on Servers
# Description: Verify licenses across configured servers
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Feb 23 2025
################################################################################


echo "Status of licenses under <SERVER> server"
echo "----Defacto----"
	/tools/lmtools/bin/lmstat -c 1700@<SERVER>
	echo "--------------"
echo "----tsmc----"
	/tools/lmtools/bin/lmstat -c 27010@<SERVER>
	echo "--------------"
echo "----proteanTecs----"
	/tools/lmtools/bin/lmstat -c 27013@<SERVER>
	echo "--------------"
echo "----Mentor----"
	/tools/lmtools/bin/lmstat -c 27015@<SERVER>
	echo "--------------"
echo "----Keysight----"
	/tools/lmtools/bin/lmstat -c 27016@<SERVER>
	echo "--------------"
echo "---Synopsys---" 
	/tools/lmtools/bin/lmstat -c 27100@<SERVER> 
	echo "--------------"
echo "---Xilinx-----"
	/tools/lmtools/bin/lmstat -c 27101@<SERVER> 
	echo "--------------"
echo "---Cadence----"		
	/tools/lmtools/bin/lmstat -c 27102@<SERVER>
	echo "--------------"
echo "----Altera----"
	/tools/lmtools/bin/lmstat -c 27103@<SERVER>
	echo "--------------"
echo "----testinsight----"
	/tools/lmtools/bin/lmstat -c 27400@<SERVER>
	echo "--------------"

echo "Complete licenses status from <SERVER> server"
	exit
	;;
