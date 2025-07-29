#!/bin/bash

################################################################################
# Export Active Users
# Description: Export list of active users from AD
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 01 2025
################################################################################

# Default Flags
print_to_screen=false
print_department=false
print_email=false
print_manager=false
print_full_name=false
print_username=false
print_gidNumber=false
print_user_description=false
print_title=false

# LDAP connection settings
ldap_server="x-dc01.exmaple.local"
bind_dn="admin@exmaple.local"
base_dn="OU=Users,OU=exmaple.local,DC=exmaple,DC=local"
ldap_pass="/home/aviela/secret/.ldap"

# Parse flags
while getopts ":demfuitap" opt; do
  case $opt in
    d) print_department=true ;;
    e) print_email=true ;;
    m) print_manager=true ;;
    f) print_full_name=true ;;
    u) print_username=true ;;
    i) print_gidNumber=true ;;
    t) print_title=true ;;
    U) print_user_description=true ;;
    a) # -a = all attributes
       print_department=true
       print_email=true
       print_manager=true
       print_full_name=true
       print_username=true
       print_gidNumber=true
       print_user_description=true
       print_title=true ;;
    p) print_to_screen=true ;;
    \?) echo "Usage: $0 [-d] [-e] [-m] [-f] [-u] [-i] [-U] [-t] [-a] [-p]" 
        exit 1 ;;
  esac
done

# Ask user for output file with timeout
echo "Enter the file path to save the output (default: /tmp/export_ad_users_with_attributes.csv): "
read -t 100 user_input
if [ -z "$user_input" ]; then
  output_file="/tmp/export_ad_users_with_attributes.csv"
else
  output_file="$user_input"
fi

# LDAP search for enabled users
ldap_result=$(ldapsearch -LLL -x -h "$ldap_server" -D "$bind_dn" -y $ldap_pass -b "$base_dn" \
  "(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" \
  #"(&(objectClass=user)(userAccountControl=66048))" \
  sAMAccountName cn department mail manager gidNumber description title)

# Print header
header="Username"
$print_full_name && header="$header,Full Name"
$print_department && header="$header,Department"
$print_email && header="$header,Email"
$print_manager && header="$header,Manager"
$print_gidNumber && header="$header,UID"
$print_user_description && header="$header,User Description"
$print_title && header="$header,Title"

# Write header
echo "$header" > "$output_file"
$print_to_screen && printf "%-20s" $(echo "$header" | tr ',' ' ') && echo

# Parse LDAP output into users
current_user=""
declare -A user_info

# Process each line
while IFS= read -r line; do
  if [[ -z "$line" ]]; then
    # End of one user entry, print collected info

    output=""

    # Always add username
    output="${user_info[sAMAccountName]:-N/A}"

    $print_full_name && output="$output,${user_info[cn]:-N/A}"
    $print_department && output="$output,${user_info[department]:-N/A}"
    $print_email && output="$output,${user_info[mail]:-N/A}"
    $print_manager && 
      manager_cn=$(echo "${user_info[manager]}" | awk -F',' '{print $1}' | sed 's/CN=//') &&
      output="$output,${manager_cn:-N/A}"
    $print_gidNumber && output="$output,${user_info[gidNumber]:-N/A}"
    $print_user_description && output="$output,${user_info[description]:-N/A}"
    $print_title && output="$output,${user_info[title]:-N/A}"

    echo "$output" >> "$output_file"

    if $print_to_screen; then
      IFS=',' read -ra columns <<< "$output"
      for col in "${columns[@]}"; do
        printf "%-25s" "$col"
      done
      echo
    fi

    # Reset user_info
    unset user_info
    declare -A user_info
  else
    # Extract field and value
    key=$(echo "$line" | cut -d: -f1)
    value=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
    user_info[$key]="$value"
  fi
done <<< "$ldap_result"

echo "Export completed successfully. File saved to: $output_file on the <SERVER>"
