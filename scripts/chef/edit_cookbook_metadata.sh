#!/bin/bash

################################################################################
# Edit Cookbook Metadata
# Description: Update Chef metadata.rb file interactive and flags
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: May 11 2025
################################################################################

COOKBOOK_BASE="/tools/IT/chef-repo/cookbooks"
# COOKBOOK_BASE="/home/aviela/chef_inf02/cookbooks"
COOKBOOKS=("auth" "autofs" "sshd" "ubuntu" "citrix" "sudoers" "display" "packages" "sys_config" "zebu")

# --- Functions ---

print_usage() {
    echo "Usage: $0 -cookbook <cookbook> [-y]"
    echo ""
    echo "Options:"
    echo "  -cookbook <cookbook>   Cookbook name to update"
    echo "  -y                     Automatically confirm version bump (non-interactive)"
    echo ""
    echo "Available cookbooks:"
    printf "  %s\n" "${COOKBOOKS[@]}"
}

select_cookbook_interactive() {
    echo "Available cookbooks:"
    select cb in "${COOKBOOKS[@]}"; do
        if [[ -n "$cb" ]]; then
            cookbook="$cb"
            break
        else
            echo "Invalid selection"
        fi
    done
}

confirm_interactive() {
    read -rp "Are you sure you want to update the metadata.rb version for '$cookbook'? (yes/no): " confirm
    [[ "$confirm" == "yes" ]]
}

# --- Custom Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -cookbook)
            cookbook="$2"
            shift 2
            ;;
        -y)
            confirm_yes=true
            shift
            ;;
        -h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# --- Validation and Confirmation ---
if [[ -z "$cookbook" ]]; then
    select_cookbook_interactive
fi

if [[ ! " ${COOKBOOKS[*]} " =~ " $cookbook " ]]; then
    echo "Error: Invalid cookbook '$cookbook'"
    print_usage
    exit 1
fi

if [[ -z "$confirm_yes" ]]; then
    if ! confirm_interactive; then
        echo "Aborted by user."
        exit 0
    fi
fi

# --- SSH Version Bump Logic ---
ssh x-infra02 /bin/bash <<EOF
COOKBOOK_BASE="$COOKBOOK_BASE"
cookbook="$cookbook"
metadata_file="\$COOKBOOK_BASE/\$cookbook/metadata.rb"

if [[ ! -f "\$metadata_file" ]]; then
    echo "Error: File not found - \$metadata_file"
    exit 1
fi

current_version=\$(grep -E "^version '([0-9]+\.){2}[0-9]+'" "\$metadata_file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

if [[ -z "\$current_version" ]]; then
    echo "Error: No version found in \$metadata_file"
    exit 1
fi

IFS='.' read -r major minor patch <<< "\$current_version"
patch=\$((patch + 1))

if [[ "\$patch" -gt 99 ]]; then
    patch=1
    minor=\$((minor + 1))
fi

new_version="\$major.\$minor.\$patch"

sed -i "s/^version '.*'/version '\$new_version'/" "\$metadata_file"

echo "Updated \$cookbook: \$current_version → \$new_version"
EOF

echo "Metadata '$cookbook' updated."
