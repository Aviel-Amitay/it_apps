#!/bin/bash

while  [[ $HOSTNAME = x-infra01 ]] || [[ $HOSTNAME = x-infra01.amitay.dev ]] || [[ $HOSTNAME = xsit-vnc01 ]] || [[ $HOSTNAME = xsit-vnc01.amitay.dev ]] 
do
read -p "Welcome! Please choose action from the list: 
1  - Bootstrap a machine
2  - New VM
3  - Run Chef Client
4  - Edit Cookbook Metadata
5  - Upload Cookbook
6  - Edit Chef Node
7  - Delete VM(and remove from Chef)
8  - Create project directory
9  - Setup Linux Environment For User
10 - Add New User to Active Directory
11 - Check Licenses Servers Status
12 - SGE Actions
13 - Compare RPMs between hosts
14 - Run Speed Test
:" target


case "$target" in


	1) read -p "Insert hostname: " machine
		read -p "What role to use:
		1 - dev-servers
		2 - personal-vnc2
		3 - recipe - servers_maintenance2
		4 - recipe - xps-lab
		5 - recipe - softpower-vnc
		6 - no config, only bootstrap
		:" roletype
		case "$roletype" in
				1)
           			if nslookup $machine ; then
				echo "Bootstraping $machine now ..."
				cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never --run-list 'recipe[servers_maintenance2::autofs-249],role[dev-servers]'
				echo "DONE" ; exit
	   			else
					echo "Cannot find such hostname on DNS server!"
					exit
	   			fi
				;;
				2)
				if nslookup $machine ; then
                                echo "Bootstraping $machine now ..."
                                cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never  --run-list 'role[personal-vnc2]'
                                echo "DONE" ; exit
                                else
                                        echo "Cannot find such hostname on DNS server!"
                                        exit
                                fi
				;;
				3)
				if nslookup $machine ; then
                                echo "Bootstraping $machine now ..."
                                cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never  --run-list 'recipe[servers_maintenance2]'
                                echo "DONE" ; exit
                                else
                                        echo "Cannot find such hostname on DNS server!"
                                        exit
                                fi
                                ;;
				4) 
                                if nslookup $machine ; then
                                echo "Bootstraping $machine now ..."
                                cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never  --run-list 'role[xps-lab]'
                                echo "DONE" ; exit
                                else
                                        echo "Cannot find such hostname on DNS server!"
                                        exit
                                fi
                                ;;
				5) 
                                if nslookup $machine ; then
                                echo "Bootstraping $machine now ..."
                                cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine --node-name $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never  --run-list 'role[dev-servers-249]'
                                echo "DONE" ; exit
                                else
                                        echo "Cannot find such hostname on DNS server!"
                                        exit
                                fi
                                ;;
				6)
				if nslookup $machine ; then
                                echo "Bootstraping $machine now ..."
                                cd  /tools/IT/chef-repo ; sudo knife bootstrap $machine -i /root/.ssh/id_rsa --ssh-verify-host-key never  --node-name $machine 
                                echo "DONE" ; exit
                                else
                                        echo "Cannot find such hostname on DNS server!"
                                        exit
                                fi
				;;
		esac
	;;
	2) read -p "Insert hostname: " vm
	   read -p "Choose vm type:
1 - Standrad VLSI(CentOS 7.6)
2 - EPP Software9Ubuntu 18.04)
:" vmtarget
	   case "$vmtarget" in
	   1)
	   read -p "Use dhcp or static ip[Dhcp/Static]?" -n 1 -r
	   echo    # (optional) move to a new line
		if [[ $REPLY =~ ^[Dd]$ ]]
		then
		cd /tools/IT/chef-repo ; sudo knife vsphere vm clone $vm --template xsXXX-vnc01-c76 --bootstrap --run-list 'role[personal-vnc2]' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec personal-vnc --dest-folder /Display-VNC01
    		echo "DONE" ; exit
		else
		read -p "Insert IP address: " ip
		cd /tools/IT/chef-repo ;  sudo knife vsphere vm clone $vm --template xsXXX-vnc01 --bootstrap --run-list 'role[infra]' --datastore ds08 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips "$ip"/16 --cgw 192.168.255.254 --cspec static-ip
		echo "DONE" ; exit
		fi
            ;;
	    2)
            cd /tools/IT/chef-repo ; knife vsphere vm clone $vm --template epp_tmpl_v4 -f EPP-SW --bootstrap --run-list 'recipe[epp_ubuntu]' --datastore ds05 --start --ssh-verify-host-key never --ssh-identity-file /root/.ssh/id_rsa --cips dhcp --cspec eppxxx-vm --dest-folder /EPP-SW
	    echo "DONE!" ; exit
            ;;
 	esac
	;;
	3) read -p "Run Chef Client on[vnc/dev/infra/xps/249/all]: " cheftarget
		case "$cheftarget" in

		vnc) cd /tools/IT/chef-repo ; sudo knife ssh "role:personal-vnc" "chef-client"
		     cd /tools/IT/chef-repo ; sudo knife ssh "role:personal-vnc2" "chef-client"
			echo "DONE" ; exit
		;;
		dev) cd /tools/IT/chef-repo ; sudo knife ssh "role:dev-servers" "chef-client"
                        echo "DONE" ; exit
                ;;
		infra) cd /tools/IT/chef-repo ; sudo knife ssh 'ipaddress:192.168.1.*' "chef-client"
                        echo "DONE" ; exit
                ;;
		xps) cd /tools/IT/chef-repo ; sudo knife ssh "role:xps-lab" "chef-client"
			echo "DONE" ; exit
		;;
                249) cd /tools/IT/chef-repo ; sudo knife ssh "role:dev-servers-249" "chef-client"
                        echo "DONE" ; exit
                ;;

		all) cd /tools/IT/chef-repo ; sudo knife ssh "name:*" "chef-client"
                        echo "DONE" ; exit
                ;;
		esac
	;;
	4) read -p "Choose cookbook:
                        1] servers-maintenance(for vlsi vnc/lx machines)
                        2] servers_maintenance2(for vlsi new vnc machines)
                        3] ubuntu-xps(for sv lab machines) 
                        4] ubuntu-x1(for sv-X1 lab machines) 
                        --> " c_name
           case "$c_name" in
           1)
	   vim /tools/IT/chef-repo/cookbooks/servers-maintenance/metadata.rb
           ;;
           2)
	   vim /tools/IT/chef-repo/cookbooks/servers_maintenance2/metadata.rb
           ;;
           3)
	   vim /tools/IT/chef-repo/cookbooks/ubuntu-xps/metadata.rb
           ;;
	   4)
	   vim /tools/IT/chef-repo/cookbooks/ubuntu-x1/metadata.rb
           esac 
	;;
	5) read -p "Choose cookbook:
			1] servers-maintenance(for vlsi vnc/lx machines)
			2] servers_maintenance2(for vlsi new vnc machines)
			3] ubuntu-xps(for sv lab machines) 
			4] ubuntu-x1(for sv-X1 lab machines) 
			5] server-249(DMZ)
			6] 1+2
		        --> " c_name
	   case "$c_name" in
	   1)
	   cd /tools/IT/chef-repo ; knife cookbook upload servers-maintenance
	   echo "DONE" ; exit
	   ;;
	   2)
           cd /tools/IT/chef-repo ; knife cookbook upload servers_maintenance2
           echo "DONE" ; exit
           ;;
	   3)
	   cd /tools/IT/chef-repo ; knife cookbook upload ubuntu-xps
           echo "DONE" ; exit
	   ;;
           4)
           cd /tools/IT/chef-repo ; knife cookbook upload ubuntu-x1
           echo "DONE" ; exit
           ;;
	   5)
	   cd /tools/IT/chef-repo ; knife cookbook upload servers-249
           echo "DONE" ; exit
	   ;;
	   6)
	   cd /tools/IT/chef-repo ; knife cookbook upload servers-maintenance ; cd /tools/IT/chef-repo ; knife cookbook upload servers_maintenance2
	   echo "DONE" ; exit
	   esac
	;;
	6) read -p "Insert node name: " noden
	   cd /tools/IT/chef-repo ; sudo knife node edit $noden 
	   exit
	;;
	7) read -p "Insert vm name: " vmn
	   cd /tools/IT/chef-repo ; sudo knife vsphere vm delete $vmn -P
	   echo "DONE" ; exit
	;;
	8)read -p "Insert project name: " p_name
	  read -p "Insert owner name[cad/$p_name]: " o_name
	  read -p "Insert group permissions[domain users/"$p_name"_grp]: " g_name
	  mount x-filer001:/vol001/ /it/mnt/x-filer01/vol001
	  cd /it/mnt/x-filer01/vol001/projects
	  mkdir $p_name
	  cd $p_name
	  mkdir bin  home  master  svn  tools  work
	  cd /it/mnt/x-filer01/vol001/projects ; chown -R $o_name:"$g_name" $p_name
	  cd /it/mnt/x-filer01/vol001/projects/"$p_name"/svn ; ln -s /svn/"$p_name" "$p_name"
	  umount /it/mnt/x-filer01/vol001
	  echo "$p_name  x-filer001:/vol001/projects/&" >> /root/chef-repo/cookbooks/servers-maintenance/templates/auto.vol001.erb
	  echo "$p_name  x-filer001:/vol001/projects/&" >> /root/chef-repo/cookbooks/servers_maintenance2/templates/auto.vol001.erb
	  echo " "
	  echo "> Updating chef config files in chef server..."
	  cd /tools/IT/chef-repo ; knife cookbook upload servers_maintenance2
	  cd /tools/IT/chef-repo ; knife cookbook upload servers-maintenance
	  echo "Done!"
	  
	  echo "Project directory creation is done! To deploy the project to the servers run chef-client(on the targets) "
	  echo "--> please note SVN repo for $p_name needs to be create separately."
	  exit
	;;
	9) sh /tools/IT/bin/newuser.sh ; exit
	;;
	10)
	
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
	dn="CN=$fname,OU=Users,OU=example.local,DC=example,DC=local"
	mng="CN=$manager,OU=Users,OU=example.local,DC=example,DC=local"
	sw="CN=sw,OU=Groups,OU=example.local,DC=example,DC=local"
	vlsi="CN=vlsi,OU=Groups,OU=example.local,DC=example,DC=local"
	rnd="CN=R&D-All,OU=Groups,OU=example.local,DC=example,DC=local"
	vpn="CN=VPN_Users,OU=Groups,OU=example.local,DC=example,DC=local"

	echo "Username: "$username
	echo "Password: "$pass

	case $depart in
		"SW")
		grp="CN=sw,OU=Groups,OU=example.local,DC=example,DC=local"
		;;
		"VLSI")
		grp="CN=vlsi,OU=Groups,OU=example.local,DC=example,DC=local"
		;;
	esac

	ssh -l administrator@amitay x-dc01 "dsadd user "CN=$fname,OU=Users,OU=example.local,DC=example,DC=local" -samid $username -upn $username@amitay.dev -fn $fname -ln $lname -display $fname -disabled no -pwd $pass -dept $depart -email $username@amitay.dev -tel $phone -title $title -memberof $grp $rnd $vpn "
	echo "Account for $fname $lname is ready.
		Username:	$username
		Password:	$pass
		Department:	$depart
		Manager:	
		Phone Number:	$phone" | mail -s "Amitay.dev - New Account Created!" it@amitay.dev
	exit
	;;
	11)
	echo "---Synopsys---" 
	lmstat -c 27100@x-lic03 
	echo "--------------"
	echo "---Xilinx-----"
	lmstat -c 27101@x-lic03 
	echo "--------------"
	echo "---Cadence----"		
	lmstat -c 27102@x-lic03
	echo "--------------"
        echo "----Altera----"
	lmstat -c 27103@x-lic03
	exit
	;;
	12)
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
	13)
		read -p "Insert first hostname: " lx1
		read -p "Insert second hostname: " lx2
	        sudo /tools/IT/bin/rpmscomp --diffonly @"$lx1" @"$lx2"
		exit
	;;
	14) curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python - ; exit
	;;
	[a-z][A-Z]) echo "Please insert valid option"
	;;
esac
done
echo "Please use x-infra01"

