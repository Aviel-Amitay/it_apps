#!/bin/bash

################################################################################
# Automate External Backup
# Description: Automate backup to an external device or location
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Jun 03 2025
################################################################################

# set -x # For debug

# === Config ===
DEFAULT_RETENTION=60
BACKUP_SRC="/mnt/backups"
DISK_OPTIONS=("192.168.130.134:/backup" "192.168.130.135:/backup")
MOUNT_POINTS=("/mnt/bck04" "/mnt/bck05")

# === Update user who initial the process ===
if [[ -z "$SCRIPT_USER" ]]; then
    echo ""
    echo "Please enter the username of the person who initiated this setup (e.g., aviela):"
    echo ""
    read -rp "Username: " SCRIPT_USER

    # Validate non-empty input
    if [[ -z "$SCRIPT_USER" ]]; then
        echo "Error: Username cannot be empty. Exiting."
        exit 1
    fi
fi

# User info
SUFFIX="amitay.dev"
SCRIPT_USER_EMAIL="${SCRIPT_USER}@"$SUFFIX""
EMAIL_RECIPIENTS=( "aviela@$SUFFIX" "it@$SUFFIX" "$SCRIPT_USER_EMAIL" )
EMAIL_RECIPIENTS_EXTERNAL=( "aviela@$SUFFIX" "it@$SUFFIX" "info@example.co.il" "$SCRIPT_USER_EMAIL" )

# === Auto-Detect Connected Backup Disks ===
AVAILABLE_DISKS=()
AVAILABLE_INDEXES=()

echo "Scanning for connected backup disks..."
for i in "${!DISK_OPTIONS[@]}"; do
    DISK_IP=${DISK_OPTIONS[$i]%:*}
    ping -c 1 -W 2 "$DISK_IP" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        AVAILABLE_DISKS+=("${DISK_OPTIONS[$i]}")
        AVAILABLE_INDEXES+=("$i")
    fi
done

if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
    echo "❌ No backup disks are reachable. Please check the connections."
    exit 1
elif [[ ${#AVAILABLE_DISKS[@]} -eq 1 ]]; then
    index=${AVAILABLE_INDEXES[0]}
    echo "✅ Detected available disk: ${DISK_OPTIONS[$index]} -> ${MOUNT_POINTS[$index]}"
    echo "Auto-selected this disk."
    choice=$((index + 1))
else
    echo "Multiple disks detected. Please choose:"
    for i in "${!AVAILABLE_DISKS[@]}"; do
        idx=${AVAILABLE_INDEXES[$i]}
        echo "$((idx+1))) ${DISK_OPTIONS[$idx]} -> ${MOUNT_POINTS[$idx]}"
    done
    read -rp "Enter choice [1 or 2]: " choice
fi

# === Set Disk Variables Based on Choice ===
if [[ "$choice" != "1" && "$choice" != "2" ]]; then
    echo "❌ Invalid choice."
    exit 1
fi

DISK_IP=${DISK_OPTIONS[$((choice-1))]%:*}
MOUNT_PATH=${MOUNT_POINTS[$((choice-1))]}
NFS_EXPORT=${DISK_OPTIONS[$((choice-1))]}

echo ""
echo "Selected mount point: $MOUNT_PATH"
echo "NFS export: $NFS_EXPORT"
echo ""

# === Confirm Firmware and Unlock ===
read -rp "Have you updated to the latest firmware? (yes/no): " firmware_ok
read -rp "Have you unlocked the disk? (yes/no): " unlock_ok

if [[ "$firmware_ok" != "yes" || "$unlock_ok" != "yes" ]]; then
    echo "Please update firmware and unlock the disk first. Exiting."
    exit 1
fi

# === Ask for Custom Retention Days ===
read -rp "Enter number of days to retain (default: $DEFAULT_RETENTION): " RETENTION
RETENTION=${RETENTION:-$DEFAULT_RETENTION}
echo "Using retention period: $RETENTION days"


# === Confirm Deletion of Old Data (LOCAL) ===
read -rp "Delete existing contents in $MOUNT_PATH before backup? (yes/no): " confirm_delete

# If the user says "yes", we'll delete. If not, ask whether to proceed with backup.
if [[ "$confirm_delete" != "yes" ]]; then
    # User does NOT want to delete old contents
    read -rp "Do you want to perform the backup for the last $RETENTION days anyway? (yes/no): " do_backup

    if [[ "$do_backup" != "yes" ]]; then
        echo "Backup aborted by user (no deletion, no backup)."
        exit 0
    fi
else
    # If user said "yes" to delete, Delete the old backup and continue with the latest backup file process
    do_backup="yes"
fi


# === Check and Mount ===
DISK_NAME=$(basename "$MOUNT_PATH")
DATE_TAG=$(date +%Y%m%d)
REMOTE_STATUS_FILE="/tmp/status-${DISK_NAME}-${DATE_TAG}.txt"
LOCAL_STATUS_FILE="/tmp/status-${DISK_NAME}-${DATE_TAG}.txt"
rm -f /tmp/status-bck* # Delete previous files


# Pass these into SSH environment and execute the script remotely
ssh root@x-backup01 /bin/bash <<EOF
# set -x # Debug print 
hostname
ls -ld /tmp/status-bck*  # List of current files
rm -f /tmp/status-bck* # Delete previous files
ls -ld /tmp/status-bck* # Verify that not files exiting

# Injected from local shell:
NFS_EXPORT="$NFS_EXPORT"
MOUNT_PATH="$MOUNT_PATH"
DISK_IP="$DISK_IP"
EMAIL_RECIPIENTS="$EMAIL_RECIPIENTS"
EMAIL_RECIPIENTS_EXTERNAL="$EMAIL_RECIPIENTS_EXTERNAL"
BACKUP_SRC="$BACKUP_SRC"
RETENTION="$RETENTION"
SCRIPT_USER="$SCRIPT_USER"
CONFIRM_DELETE="$confirm_delete"
DO_BACKUP="$do_backup"

DISK_NAME=\$(basename "\$MOUNT_PATH")
DATE_TAG=\$(date +%Y%m%d)
REMOTE_STATUS_FILE="/tmp/status-\${DISK_NAME}-\${DATE_TAG}.txt"

touch "\$REMOTE_STATUS_FILE"
chmod 600 "\$REMOTE_STATUS_FILE"

# Ensure mount point exists
if [[ ! -d "\$MOUNT_PATH" ]]; then
    echo "Creating mount point directory: \$MOUNT_PATH"
    mkdir -p "\$MOUNT_PATH"
fi

# Mount if not already mounted
if ! mountpoint -q "\$MOUNT_PATH"; then
    echo "Mounting \$NFS_EXPORT to \$MOUNT_PATH..."
    MOUNT_OUTPUT=\$(timeout 10s mount -t nfs "\$NFS_EXPORT" "\$MOUNT_PATH" 2>&1)
    MOUNT_EXIT=\$?

    if [[ "\$MOUNT_EXIT" -ne 0 ]]; then
        if echo "\$MOUNT_OUTPUT" | grep -qi "Connection refused"; then
            ERROR_MSG="Mount failed: Connection refused to \$DISK_IP."
        elif echo "\$MOUNT_OUTPUT" | grep -qi "access denied"; then
            ERROR_MSG="Mount failed: Access denied. Disk might be locked."
        elif echo "\$MOUNT_OUTPUT" | grep -qi "reason given by server"; then
            ERROR_MSG="Mount failed: Reason given by server. Disk might be locked."
        elif echo "\$MOUNT_OUTPUT" | grep -qi "/dev/sda3"; then
            ERROR_MSG="Mount failed: /dev/sda3. Disk is not mounted."
        elif [[ "\$MOUNT_EXIT" -eq 124 ]]; then
            ERROR_MSG="Mount timed out. Network or NFS server issue."
        else
            ERROR_MSG="Mount failed with unexpected error: \$MOUNT_OUTPUT"
        fi

        echo "\$ERROR_MSG"
        echo "MOUNT_ERROR=\"\$ERROR_MSG\"" >> "\$REMOTE_STATUS_FILE"
        echo "MOUNT_OUTPUT=\"\$MOUNT_OUTPUT\"" >> "\$REMOTE_STATUS_FILE"
        exit 1
    else
        echo "Mounted successfully."
        echo "MOUNT_OK=true" >> "\$REMOTE_STATUS_FILE"
    fi
else
    echo "\$MOUNT_PATH is already mounted."
    echo "MOUNT_OK=true" >> "\$REMOTE_STATUS_FILE"
fi

# Confirm Deletion
if [[ "\$CONFIRM_DELETE" == "yes" ]]; then
    echo "Deleting old content from \$MOUNT_PATH..."
    rm -rf "\${MOUNT_PATH:?}/"*
    echo "DELETE_OLD=true" >> "\$REMOTE_STATUS_FILE"
    echo ""
else
    echo "Skipping deletion step."
fi

# Write dummy values (or rsync later)
RSYNC_EXIT=1
DISK_QUOTA="N/A"

echo "DEBUG: RSYNC_EXIT='$RSYNC_EXIT'"

if [[ "\$DO_BACKUP" == "yes" ]]; then
    echo "Starting rsync backup with \$RETENTION days retention..."
    cd "\$BACKUP_SRC" && \
    echo "\$BACKUP_SRC"
    echo ""

    find . \( -path "./new/git/scratch" -o -path "./new/git/bundled" \) -prune -o -type f -mtime "-\$RETENTION" -print0 \
    | rsync -av --files-from=- --from0 . "\$MOUNT_PATH/"

    RSYNC_EXIT=\$?
    echo "DEBUG: rsync exit code was $RSYNC_EXIT"
    
    # Evaluate rsync result
    if [[ "\$RSYNC_EXIT" -eq 0 || "\$RSYNC_EXIT" -eq 24 ]]; then
    # if [[ $RSYNC_EXIT -eq 0 || $RSYNC_EXIT -eq 24 ]]; then
        echo "RSYNC_OK=true" >> "$REMOTE_STATUS_FILE"
    else
        echo "RSYNC_OK=false" >> "$REMOTE_STATUS_FILE"
    fi

    # Disk Usage
    DISK_QUOTA=\$(df -h "\$MOUNT_PATH" | awk 'NR==2 { print "Used: " \$3 " / Total: " \$2 " (" \$5 " used)" }')
    echo "DISK_QUOTA=\"\$DISK_QUOTA\"" >> "\$REMOTE_STATUS_FILE"
    echo "**Notification from remote host** Disk usage: \$DISK_QUOTA"
else
    echo "Skipping backup as per user choice."
    echo "RSYNC_OK=false" >> "$REMOTE_STATUS_FILE"
    echo "DISK_QUOTA=\"$DISK_QUOTA\"" >> "$REMOTE_STATUS_FILE"
    RSYNC_EXIT=2
    echo "Backup failure, the disk usgae: $DISK_QUOTA"
fi

echo "RSYNC_EXIT=\$RSYNC_EXIT" >> "\$REMOTE_STATUS_FILE"

EOF


# === Copy Remote Status File Locally ===
if scp root@x-backup01:"$REMOTE_STATUS_FILE" "$LOCAL_STATUS_FILE"; then
    echo "Status file copied successfully."
else
    echo "❌ Failed to retrieve status file from remote host." >&2
    exit 1
fi

# === Source Status Values ===
if [ -f "$LOCAL_STATUS_FILE" ]; then
    source "$LOCAL_STATUS_FILE"
    echo "$LOCAL_STATUS_FILE source succssfully"
else
    echo "❌ Local status file not found: $LOCAL_STATUS_FILE" >&2
    exit 1
fi

if grep -q '^MOUNT_ERROR=' "$LOCAL_STATUS_FILE"; then
    MOUNT_ERROR=$(grep '^MOUNT_ERROR=' "$LOCAL_STATUS_FILE" | cut -d'=' -f2- | sed 's/^"//;s/"$//')

    # Send mail from local host
    echo "$MOUNT_ERROR" | mail -s "Backup Failed: Mount Error ($DISK_NAME)" -- "${EMAIL_RECIPIENTS[@]}"
    echo "$MOUNT_ERROR"
    rm -f "$LOCAL_QUOTA_FILE" ; ssh root@x-backup01 "rm -f $REMOTE_QUOTA_FILE"
    exit 1
fi

# === Extract Disk Usage Info ===
if grep -q '^DISK_QUOTA=' "$LOCAL_STATUS_FILE" ; then
    DISK_QUOTA=$(grep '^DISK_QUOTA=' "$LOCAL_STATUS_FILE" | cut -d'=' -f2- | sed 's/^"//;s/"$//')
    echo "Disk usage: '$DISK_QUOTA'"
fi

# === Prepare Email Body ===
gecos=$(getent passwd "$SCRIPT_USER" | cut -d: -f5 | awk '{print $1}' 2>/dev/null)
EMAIL_BODY=$(cat <<EOF
Hi,

Backup disk $DISK_NAME is ready for pickup.
Please return with you the second backup disk.

Contact info:
Sagi - 054-3109634
Dvir - 054-6800987

Internal note - Backup days: $RETENTION.
Disk usage: 
$DISK_QUOTA


BR,
$gecos
EOF
)

# === Send Completion Email ===
if [[ "$RSYNC_OK" == "true" ]]; then
    # If rsync completed successfully
    echo "Email will send to the following: ${EMAIL_RECIPIENTS_EXTERNAL[@]}"
    echo ""
    echo "$EMAIL_BODY"

    # Send email to external recipients
    # echo "$EMAIL_BODY" | mail -s "External Backup disk '$DISK_NAME' ready to Pickup" "${EMAIL_RECIPIENTS[@]}"
    echo "$EMAIL_BODY" | mail -s "External Backup disk '$DISK_NAME' ready to Pickup" "${EMAIL_RECIPIENTS_EXTERNAL[@]}"
else
    # Send failure message
    echo "Backup failed (rsync error)" | mail -s "Backup Failed to $MOUNT_PATH with disk $DISK_NAME" "${EMAIL_RECIPIENTS[@]}"
fi
