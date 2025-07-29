#!/bin/bash

################################################################################
# Update Autofs Maps
# Description: Update Autofs map configurations and reload maps
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jun 09 2025
################################################################################

#########################
# Global Configuration #
#########################

LOCK_CREATED_BY_ME=0

create_lock() {
    # echo "$$" > "$LOCK_FILE"
    echo "$it_username" > "$LOCK_FILE"
    LOCK_CREATED_BY_ME=1
}

remove_lock () {
    rm -rf "$LOCK_FILE"
}

set_defaults () {
    tab=$'\t'
    new_line=$'\n'

    DEV=1
    LOCK_FILE="/tools/IT/it_services.lock"
    # LOCK_FILE="/tools/IT/it_services1.lock"

    # Git
    MAIN_BRANCH="master"
    CHEF_DIR="/tools/IT/chef-repo/"
    # CHEF_DIR="/tools/IT/chef-automate-2d/"

    username=""
    project=""
    department=""
    copy_user=""
}

is_data_in_argv () {
    if [[ ! $# -gt 0 ]]; then
        echo "No args in command line argv"
        return 1
    fi
    return 0
}

validate_args () {
    get_args "$@" 
    echo "args = $@"
    echo "user = $username, project = $project"
    
    if [[ -z "$username" || -z "$project" ]]; then
        echo "Username or Project is missing"
        echo "Requesting data from user"
        request_from_user
    fi
}

request_from_user () {
    [[ -z "$username" ]] && read -p "Username: " username
    [[ -z "$project" ]] && read -p "Project: " project
    [[ -z "$copy_user" ]] && read -p "Copy user info: " copy_user
    [[ -z "$department" ]] && read -p "Department (optional): " department
    # [[ -z "$map_type" ]] && read -p "Type (work|home): " map_type
}

help () {
    help="USAGE: $(basename "$0") [OPTIONS]"$new_line$new_line
    help+=$tab"Can run in interactive mode with no flags"$new_line
    help+=$tab"Can run in automatic mode with flags"$new_line$new_line
    help+="OPTIONS:"$new_line
    help+=$tab"-u/-user | User to create map entry for"$new_line
    help+=$tab"-p/-proj | Project to find map file"$new_line
    help+=$tab"-whoami  | Enter the username of the person who initiated this setup"$new_line
    help+=$tab"-d/-dept | Department for scanning map file (optional)"$new_line
    help+=$tab"-c/-copy | Username to copy map entry from"$new_line
    help+=$tab"-h/-help | Shows this help message"$new_line
    # printf "$help"
    clean_exit "$help" 0
}

get_args () {
    while [[ $# -gt 0 ]]; do
        arg="$1"
        shift
        if [[ "$arg" == -* ]]; then
            case "$arg" in
                -h|-help) help ;;
                -u|-user) username="$1"; shift ;;
                -p|-proj|-project) project="$1"; shift ;;
                -whoami) it_username="$1"; shift ;;
                -d|-dept) department="$1"; shift ;;
                -c|-copy) copy_user="$1"; shift ;;
                *) clean_exit "Unknown argument $arg" 1 ;;
            esac
        fi
    done
}

#############
# Template #
#############

get_project_template () {
    COOKBOOKS_DIR="$CHEF_DIR/cookbooks"
    AUTOFS_TEMPLATES_DIR="$COOKBOOKS_DIR/autofs/templates"
    echo "Running external script from path: $CHEF_DIR"
    echo ""

    # auto-discovery failed or -t flag not provided == no value for $selected_template
    if [[ -z "$selected_template" ]]; then
         project_templates=("$AUTOFS_TEMPLATES_DIR/auto.project.$project.work.erb")

        if [[ ${#project_templates[@]} -eq 0 ]]; then
            msg="No templates found for project: $project"
            clean_exit "$msg" 1
        elif [[ ${#project_templates[@]} -eq 1 ]]; then
            echo "Only one template found. Automatically selecting it."
            selected_template="${project_templates[0]}"
        else
            echo "Multiple templates found for $project:"
            for i in "${!project_templates[@]}"; do
                echo "[$i] $(basename ${project_templates[$i]})"
            done
            
            selected_template="${project_templates[$choice]}"
        fi
    fi

    echo "Selected template: $(basename $selected_template)"
    echo ""
}

###################
# Copy user info #
###################

get_copy_user_line () {
    if [[ -z "$copy_user" ]]; then
        msg="Error: copy_user is empty."
        clean_exit "$msg" 1
    fi

    # Extract the copy_user's full line from the template
    copy_user_line=$(grep -E "^${copy_user}\b" "$selected_template")

    # If user not found, invoke interactive selection
    if [[ -z "$copy_user_line" ]]; then
        echo "Error: copy_user_line is empty. User $copy_user not found in $selected_template"
        echo "Falling back to manual user selection from available entries..."

        request_copy_user
        if [[ $? -ne 0 ]]; then
            echo "User selection cancelled or failed. Returning to main script."
            return 1
        fi

        # Extract updated values from the new selection
        copy_user=$(echo "$selected_copy_user" | awk -F ' - ' '{print $1}')
        entry=$(echo "$selected_copy_user" | awk -F ' - ' '{print $2}')
        copy_user_line="$copy_user $entry"

        echo "Using fallback user: $copy_user"
    fi


    # if [[ -z "$copy_user_line" ]]; then
    #     msg="Error: copy_user_line is empty. User $copy_user not found in $selected_template"
    #     clean_exit "$msg" 1
    # fi

    echo "Found line: $copy_user_line"

    # Create the new line by replacing both the mount point and NFS path username
    new_line=$(echo "$copy_user_line" | sed -E "s/^$copy_user\b/$username/; s|/users/$copy_user\b|/users/$username|")

    # Avoid duplication if user already exists
    if grep -q -E "^$username\b" "$selected_template"; then
        echo ""
        echo "*** User $username already exists in $selected_template. Skipping add and Git steps. ***"
        echo ""
        user_exists=1
        # Track touched file even if not modified (optional but useful for consistency)
        TOUCHED_PROJECTS+=("$project")
        SELECTED_TEMPLATES+=("$selected_template")
        return 0
    fi

    # Escape characters for safe pattern matching
    escaped_copy_user_line=$(printf '%s\n' "$copy_user_line" | sed 's/[\/&]/\\&/g')

    # Append the new line after the copied line
    if [[ $DEV -eq 0 ]]; then
        sed -i "/$escaped_copy_user_line/a\\
$new_line" "$selected_template"
    else
        tmp_file="${selected_template}.tmp"
        sed "/$escaped_copy_user_line/a\\
$new_line" "$selected_template" > "$tmp_file" && mv "$tmp_file" "$selected_template"
    fi

    echo "Added new line: $new_line"
    user_exists=0
    return 0
}


request_copy_user () {
    # Ensure the file exists
    if [[ ! -f "$selected_template" ]]; then
        echo "Error: Selected template file '$selected_template' does not exist."
        return 1
    fi

    # Read the file and filter lines
    copy_users=()
    while IFS= read -r line; do
        # Skip lines starting with '#' or '*'
        if [[ "$line" =~ ^[#\*] ]]; then
            continue
        fi

        # Extract the first element (split by whitespace)
        first_element=$(basename $(echo "$line" | awk '{print $1}'))
        entry=$(echo "$line" | awk '{print $2}')
        if [[ -n "$first_element" ]]; then
            copy_users+=("$first_element - $entry")
        fi
    done < "$selected_template"

    # Check if any valid users were found
    if [[ ${#copy_users[@]} -eq 0 ]]; then
        echo "No valid copy users found in the template."
        return 1
    fi

    # Display options to the user
    echo "Available copy users:"
    for i in "${!copy_users[@]}"; do
        echo "$((i + 1)). ${copy_users[i]}"
    done

    # Request user input
    echo -n "Enter the number of the copy user to select: "
    read -r selection

    # Validate input
    if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#copy_users[@]})); then
        selected_copy_user="${copy_users[$((selection - 1))]}"
        echo "You selected: $selected_copy_user"
        copy_user="$selected_copy_user"
        return 0
    else
        echo "Invalid selection. Exiting."
        return 1
    fi
}

#######
# GIT #
#######

git_status_check () {
    cd "$CHEF_DIR" || { clean_exit "Error: Failed to change to directory $CHEF_DIR" 1; }

    # Get prod branch
    echo "Getting production branch '$MAIN_BRANCH'"
    git pull origin "$MAIN_BRANCH" >/dev/null 2>&1

    # Skip check if lock held by same user
    if [[ "$LOCK_HELD_BY_ME" -eq 1 ]]; then
        echo "Skipping git status check: lock already held by you ($it_username)"
        return 0
    fi

    # Check for untracked files or uncommitted changes
    if git status --porcelain | grep -qE '^\s*[AM?]'; then
        msg="Untracked files or uncommitted changes detected. Please review git repo at $CHEF_DIR"
        clean_exit "$msg" 1
    else
        echo "Git working directory clean."
    fi
}

# Commit git changes
commit_git_changes () {
    # Skip everything if user already exists AND not continuing with more projects
    if [[ "$user_exists" -eq 1 && "$CONTINUE_WITH_PROJECTS" -ne 1 ]]; then
        echo ""
        echo "***  Skipping Git operations: User $username already exists in the template. ***"
        echo ""
        return 0
    fi

    cd "$CHEF_DIR"
    echo "Switched directory to $PWD"

    # 1. Create local branch
    branch_name="'$whoami'_automate_$(date +%Y-%m-%d)"
    echo "Creating and switching to branch: $branch_name"
    git checkout -b "$branch_name"

    # 2. Stage and commit changes
    commit_msg_line1="$it_username - Cookbook autofs - updated map file $(basename "${project_templates[$i]}") for user $username"
    commit_msg_line2="* Affected projects: $project"


    echo ""
    echo "Adding file: $(basename "${project_templates[$i]}"), and file metadata.rb"
    git add "$selected_template" "$CHEF_DIR/cookbooks/autofs/metadata.rb"

    echo "Committing with message:"
    echo "$commit_msg_line1"
    echo "$commit_msg_line2"
    git commit -m "$commit_msg_line1" -m "$commit_msg_line2"

    # Save branch name for push
    echo "$branch_name" > /tmp/git_branch_to_push
    echo "Changes committed to branch: $branch_name"
    git push "$branch_name"
}

finalize_git_push () {
    branch_name=$(cat /tmp/git_branch_to_push)

    # Always run metadata update before push
    echo "Running metadata script before Git push..."
        
    metadata_script="/tools/IT/it_services/scripts/edit_cookbook_metadata.sh"
    # metadata_script="/home/aviela/it_services/scripts/edit_cookbook_metadata.sh"
    sh "$metadata_script" -cookbook autofs -y

    cd "$CHEF_DIR" || {
        echo "Error: Failed to cd into CHEF_DIR: $CHEF_DIR"
        return 1
    }
    
    echo "$PWD"
    echo ""
    
    # Check if metadata.rb was changed
    metadata_path="$CHEF_DIR/cookbooks/autofs/metadata.rb"
    if [[ -n $(git status --porcelain "$metadata_path") ]]; then
        echo "Staging and committing metadata.rb changes..."
        git add "$metadata_path"
        git commit -m "$it_username - Cookbook autofs - bump version in metadata.rb after user map update"
    else
        echo "No changes in metadata.rb to commit."
    fi

    echo "Switching back to master"
    git checkout master

    echo "Merging $branch_name into master"
    git merge --no-ff -m "Merge $branch_name into master" "$branch_name"

    echo "Pushing master branch to remote"
    git push origin master

    echo "Deleting local branch: $branch_name"
    git branch -d "$branch_name"

    rm -f /tmp/git_branch_to_push
    echo "Git push finalized successfully."
}

handle_signal() {
    # Function to handle cleanup for various signals
    local signal="$1"
    local code=""
    local msg=""

    case "$signal" in
        INT)    msg="CTRL+C detected. Cleaning up and exiting..."; code=2 ;; # SIGINT (CTRL+C)
        HUP)    msg="SIGHUP received. Reloading configuration..."; code=1 ;; # SIGHUP
        TERM)   msg="SIGTERM received. Terminating gracefully..."; code=15 ;; # SIGTERM
        QUIT)   msg="SIGQUIT received. Aborting with core dump..."; code=3 ;; # SIGQUIT
        USR1)   msg="SIGUSR1 received. Aborting with core dump..."; code=10 ;; # SIGUSR1
        USR2)   msg="SIGUSR2 received. Aborting with core dump..."; code=11 ;; # SIGUSR2
        *)      msg="Signal $signal received. Handling as default..."; code=1 ;; # Default
    esac

    clean_exit "$msg" "$code"
}

clean_exit () {
    local msg="$1"
    local code="$2"

    if [[ -n "$msg" ]]; then
        echo "$msg"
    fi

    if [[ -f "$LOCK_FILE" && "$LOCK_CREATED_BY_ME" -eq 1 ]]; then
        echo "Releasing lock"
        remove_lock
    fi

    exit "$code"
}

main () {
    # Trap various signals
    trap 'handle_signal INT' INT    # CTRL+C
    trap 'handle_signal HUP' HUP    # Hangup
    trap 'handle_signal TERM' TERM  # Termination
    trap 'handle_signal QUIT' QUIT  # Quit (with core dump)
    trap 'handle_signal USR1' USR1  # User-defined signal 1
    trap 'handle_signal USR2' USR2  # User-defined signal 2

    set_defaults
    get_args "$@"

    validate_args "$@"
    
    # Lock logic
    if [[ -f "$LOCK_FILE" ]]; then
        current_locker=$(cat "$LOCK_FILE")
        if [[ "$current_locker" == "$it_username" ]]; then
            echo "Lock already held by you ($it_username), continuing..."
            LOCK_CREATED_BY_ME=0  # Do not remove lock in clean_exit
            LOCK_HELD_BY_ME=1 # if LOCK_FILE create by the origin user, will let you procced.
        else
            msg="$LOCK_FILE exists, someone else ($current_locker) may be modifying maps"
            LOCK_CREATED_BY_ME=0
            clean_exit "$msg" 1
        fi
    else
        create_lock
        LOCK_HELD_BY_ME=1
    fi

    git_status_check
    TOUCHED_PROJECTS=()

    echo "Adding user $username to project $project"
    echo ""
    
    get_project_template

    if [[ -n "$copy_user" ]]; then
        get_copy_user_line
    else
        request_copy_user
        get_copy_user_line
    fi

    commit_git_changes

    # Initialize continuation flag
    CONTINUE_WITH_PROJECTS=0  # Used to allow git commit even if user exists

    if [[ "$user_exists" -eq 0 ]]; then
        read -p "Would you like to run the setup_linux_env script again to add more users or create additional projects? [y/n]: " confirmation

        if [[ "$confirmation" =~ ^[yY]$ ]]; then
            CONTINUE_WITH_PROJECTS=1
            TOUCHED_PROJECTS+=("$project")

            # Call setup script again and exit early, metadata will be handled after second run
            # sh /tools/IT/it_services/scripts/setup_linux_env.sh -whoami "$it_username"
            sh /home/aviela/it_services/scripts/setup_linux_env.sh -whoami "$it_username"
            echo "Re-running setup. Metadata update and git push will be handled after that step."
            exit 0
        fi
    fi

    # Merge and push changes to git     
    finalize_git_push

    clean_exit "Done" 0
}

main "$@"
