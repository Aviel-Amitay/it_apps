#!/bin/bash

################################################################################
# Compare RPMs
# Description: Compare installed RPMs across systems
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Apr 30 2025
################################################################################


# Function to detect OS type on a remote machine
detect_remote_os() {
    ssh "$1" "source /etc/os-release && echo \$ID"
}

# Prompt for hostnames
read -p "Insert first hostname: " host1
read -p "Insert second hostname: " host2

# Detect OS type remotely
OS_TYPE_HOST1=$(detect_remote_os "$host1")
OS_TYPE_HOST2=$(detect_remote_os "$host2")

# Ensure both hosts have the same OS type
if [[ "$OS_TYPE_HOST1" != "$OS_TYPE_HOST2" ]]; then
    echo "Error: The two hosts have different OS types! ($host1: $OS_TYPE_HOST1, $host2: $OS_TYPE_HOST2)"
    exit 1
fi

echo "Detected OS: $OS_TYPE_HOST1"

# Define temporary files for package lists
TMP_HOST1="/tmp/${host1}_packages.txt"
TMP_HOST2="/tmp/${host2}_packages.txt"

# Function to format package list for RHEL-based systems
fetch_rhel_packages() {
    ssh "$1" "rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'" | sort > "$2"
}

# Function to format package list for Debian-based systems
fetch_debian_packages() {
    ssh "$1" "dpkg-query -W -f='\${Package} \${Version} \${Architecture}\n'" | sort > "$2"
}

# Fetch package lists based on OS type
case "$OS_TYPE_HOST1" in
    "rhel"|"centos"|"rocky")
        echo "Fetching package lists for RHEL-based system..."
        fetch_rhel_packages "$host1" "$TMP_HOST1"
        fetch_rhel_packages "$host2" "$TMP_HOST2"
        ;;
    "debian"|"ubuntu")
        echo "Fetching package lists for Debian-based system..."
        fetch_debian_packages "$host1" "$TMP_HOST1"
        fetch_debian_packages "$host2" "$TMP_HOST2"
        ;;
    *)
        echo "Unknown OS type ($OS_TYPE_HOST1). Exiting."
        exit 1
        ;;
esac

# Create headers for formatted output with extra spaces for alignment
HEADER=$(printf "%-45s %-25s %-15s %-25s %-15s\n" "Name" "@$host1 Ver-Rel" "Arches" "@$host2 Ver-Rel" "Arches")
SEPARATOR=$(printf "%-45s %-25s %-15s %-25s %-15s\n" "---------------------------------------------" "-------------------------" "--------------" "-------------------------" "--------------")

# Print headers
echo ""
echo "Comparison between @${host1} and @${host2}"
echo "$HEADER"
echo "$SEPARATOR"

# Use join to align package names, filling missing values with "-"
join -a1 -a2 -e "-" -o '1.1 1.2 1.3 2.2 2.3' "$TMP_HOST1" "$TMP_HOST2" | awk '{printf "%-45s %-25s %-15s %-25s %-15s\n", $1, $2, $3, $4, $5}'

echo "File of hostname "$host1" you can find on the <SERVER> in "$TMP_HOST1""
echo "File of hostname "$host2" you can find on the <SERVER> in "$TMP_HOST2""

exit 0
