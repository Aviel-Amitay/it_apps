#!/bin/bash

################################################################################
# Customize Company Environment
# Description: Interactive utility to update company-specific details.
#              Includes dry-run mode with detailed logging 
#              to preview all changes safely.
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay
# Modified: Sep 25 2025
################################################################################


# set -x # Remove the comment for debug
set -euo pipefail

ROOT_DIR="/mnt/x/it_apps"
SCRIPT_BASE="$ROOT_DIR/scripts2"
LAUNCHER_FILE="$ROOT_DIR/launcher-app.sh.bk"
LOG_FILE="$ROOT_DIR/customize_company_updated.log"
DRY_RUN=false

# Parse flags
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=true
  fi
done

# "========== Logs =========="
echo ""
echo ">>> Scanning and applying replacements in: $SCRIPT_BASE"
echo ">>> Dry-run mode: $DRY_RUN"
echo ">>> Logging to: $LOG_FILE"
echo ""

> "$LOG_FILE"

echo "========== Company Configuration =========="
# ========== Auto-detect domain values across scripts ==========
  echo ""
  echo "🔍 Auto-detecting company domains from script content..."

  # --- Detect Internal AD Domain ---
  ad_domain_line=$(grep -rhoE 'OU=[a-zA-Z0-9.-]+,DC=[a-zA-Z0-9.-]+,DC=[a-zA-Z0-9.-]+' "$SCRIPT_BASE" | head -n1)

  if [[ "$ad_domain_line" =~ OU=([a-zA-Z0-9.-]+),DC=([a-zA-Z0-9.-]+),DC=([a-zA-Z0-9.-]+) ]]; then
    previous_internal_ad_domain="${BASH_REMATCH[1]}"
    echo "✔ Internal AD domain detected: $previous_internal_ad_domain"
    echo "  Full Base DN: DC=${BASH_REMATCH[2]},DC=${BASH_REMATCH[3]}"
  else
    echo "❌ No match for internal AD domain (OU=...DC=...)"
  fi

  # --- Detect External Email Domain ---
  email_domain_line=$(grep -rhoiE '[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' --exclude-dir={.git,.venv,.idea} "$SCRIPT_BASE" | \
    grep -Ev "github.com|gmail.com|username|admin|vendor.com" | head -n1)

  if [[ "$email_domain_line" =~ @([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}) ]]; then
    previous_external_email_domain="${BASH_REMATCH[1]}"
    echo "✔ External email domain detected: $previous_external_email_domain"
  else
    echo "❌ No match for external email domain (@domain)"
  fi


if [[ -z "$previous_internal_ad_domain" ]]; then
  echo "❌ ERROR: Could not detect internal AD domain from scripts."
  exit 1
fi

if [[ -z "$previous_external_email_domain" ]]; then
  echo "❌ ERROR: Could not detect external email domain from scripts."
  exit 1
fi

echo ""
echo "========== 🏷️  Detected Domain Info =========="
echo "Current AD Domain (UPN suffix): $previous_internal_ad_domain"
echo "Current Email Domain: $previous_external_email_domain"

echo "========== Update domain info for your comapny =========="
echo ""
read -t 10 -rp "Do you want to change these values? [y/N]: " change_domain
echo ""

if [[ "$change_domain" =~ ^[Yy]$ ]]; then
  read -rp "Enter NEW internal AD domain (e.g., example.local): " current_internal_ad_domain
  read -rp "Enter NEW external email domain (e.g., amitay.dev): " current_external_email_domain
else
  current_internal_ad_domain="$previous_internal_ad_domain"
  current_external_email_domain="$previous_external_email_domain"
fi

echo "--- Domain Replacement Preview ---"
echo "From AD Domain: $previous_internal_ad_domain -> $current_internal_ad_domain"
echo "From Email Domain: $previous_external_email_domain -> $current_external_email_domain"

# DC replacement block with dry-run support
read -rp "Do you want to update DC info in scripts? (y/n): " update_dc
if [[ "$update_dc" =~ ^[Yy]$ ]]; then
echo "Scanning for current user/domain/server in use..."
echo "🔍 Scanning for all admin-related user@domain values used in scripts..."

user_domain_matches=$(grep -rhoE '[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+' "$SCRIPT_BASE" --exclude-dir={.git,.venv,.idea} |
  grep -Ei 'admin|administrator' |
  grep -Ev 'gmail|vendor|example.com|example.local' |
  sort -u)

full_domain_user=""
short_domain_user=""

for line in $user_domain_matches; do
  if [[ "$line" =~ \.[a-z]{2,}$ ]]; then
    full_domain_user="$line"
  else
    short_domain_user="$line"
  fi
done

# Split both if found
if [[ -n "$full_domain_user" ]]; then
  full_user="${full_domain_user%@*}"
  full_domain="${full_domain_user#*@}"
fi

if [[ -n "$short_domain_user" ]]; then
  short_user="${short_domain_user%@*}"
  short_domain="${short_domain_user#*@}"
fi

# Display results
echo ""
echo "🧾 Detected in scripts:"
[[ -n "$full_domain_user" ]] && echo "  ✔ Full domain:   $full_user@$full_domain"
[[ -n "$short_domain_user" ]] && echo "  ✔ Short domain:  $short_user@$short_domain"

# Always prompt for domain + server
read -rp "Enter new domain (full, e.g. amitay.dev): " new_domain
read -rp "Enter new server name (e.g. x-dc01): " new_server

# Ask if user wants to change usernames
read -rp "Do you want to change the usernames? (y/n): " change_usernames

if [[ "$change_usernames" =~ ^[Yy]$ ]]; then
  read -rp "Enter new FULL username (or leave blank to keep '$full_user@$full_domain'): " new_full_user
  read -rp "Enter new SHORT username (or leave blank to keep '$short_user@$short_domain'): " new_short_user
else
  new_full_user="$full_user"
  new_short_user="$short_user"
fi

# New company parameters
new_full_user="${new_full_user:-$full_user}"
new_short_user="${new_short_user:-$short_user}"
new_domain="${new_domain:-$full_domain}"
new_server="${new_server:-unknown-server}"
new_domain_short="${new_domain%%.*}"

# Preview
echo ""
echo "--- DC Replacement Preview ---"
[[ -n "$full_domain_user" ]] && echo "  Full:  $full_user@$full_domain → $new_full_user@$new_domain"
[[ -n "$short_domain_user" ]] && echo "  Short: $short_user@$short_domain → $new_short_user@$new_domain_short"
echo "  Server: → $new_server"

# Export for later `sed` use
export DC_UPDATE_ENABLED=true
export full_user short_user full_domain short_domain
export new_full_user new_short_user new_domain new_domain_short new_server
fi

read -rp "Do you want to update the SCRIPT_BASE path in launcher files? (y/n): " update_script_base
if [[ "$update_script_base" =~ ^[Yy]$ ]]; then
  read -rp "Enter new SCRIPT_BASE absolute path (e.g., /opt/it_apps/scripts): " new_script_base
fi

# Backup process
backup_script=""
read -rp "Do you want to update the backup IPs in the automate_external_backup script file? (y/n): " update_backup_script
if [[ "$update_backup_script" =~ ^[Yy]$ ]]; then

    backup_script="$SCRIPT_BASE/automate_external_backup.sh"
    if [[ -f "$backup_script" ]]; then
      echo ""
      echo ">>> NFS Backup Disk Configuration:"
      read -rp "Enter primary NFS IP (e.g., 192.168.7.110): " nfs_ip1
      read -rp "Enter secondary NFS IP (or leave blank to skip): " nfs_ip2
    fi
fi

echo ""
echo ">>> Applying replacements in $SCRIPT_BASE ..."
echo ""

# Construct dynamic DC=... patterns
old_dc_dn="DC=${previous_internal_ad_domain//./,DC=}"
new_dc_dn="DC=${current_internal_ad_domain//./,DC=}"

# ==========================
# Build replacement patterns
# ==========================
declare -a sed_args=(
  # Replace the internal AD domain everywhere (e.g., example.local → avia.local)
  -e "s/$previous_internal_ad_domain/$current_internal_ad_domain/g"

  # Replace external email suffix (e.g., @amitay.dev → @avia.com)
  -e "s/@$previous_external_email_domain/@$current_external_email_domain/g"

  # Replace the DC=... pattern dynamically (e.g., DC=example,DC=local → DC=avia,DC=local)
  -e "s#$old_dc_dn#$new_dc_dn#g"
)

# ========================================================
# Add DC username/domain replacements if enabled by user
# ========================================================
if [[ "${DC_UPDATE_ENABLED:-false}" == "true" ]]; then

  # Full-domain replacement: e.g., admin@amitay.dev → superadmin@avia.com
  if [[ -n "${full_user:-}" && -n "${full_domain:-}" && -n "${new_full_user:-}" && -n "${new_domain:-}" ]]; then
    sed_args+=( -e "s#\\<${full_user}@${full_domain}\\>#${new_full_user}@${new_domain}#g" )
    if $DRY_RUN; then
      echo "# Full-domain replacement rule loaded: $full_user@$full_domain → $new_full_user@$new_domain" | tee -a "$LOG_FILE"
    fi
  fi

  # Short-domain replacement: e.g., administrator@amitay → sysadmin@avia
  if [[ -n "${short_user:-}" && -n "${short_domain:-}" && -n "${new_short_user:-}" && -n "${new_domain_short:-}" ]]; then
    sed_args+=( -e "s#\\<${short_user}@${short_domain}\\>#${new_short_user}@${new_domain_short}#g" )
    if $DRY_RUN; then
      echo "# Short-domain replacement rule loaded: $short_user@$short_domain → $new_short_user@$new_domain_short" | tee -a "$LOG_FILE"
    fi
  fi

  # # Server rename is optional—only add if both are set
  # if [[ -n "${current_server:-}" && -n "${new_server:-}" ]]; then
  #   sed_args+=( -e "s#\\<${current_server}\\>#${new_server}#g" )
  # fi
fi

# ==============================================
# Apply replacements (or preview if --dry-run)
# ==============================================
if [[ ${#sed_args[@]} -gt 0 ]]; then

while IFS= read -r -d '' file; do
  if $DRY_RUN; then
    echo "🔍 [DRY-RUN] Would modify: $file" | tee -a "$LOG_FILE"

    # Print context for full-domain matches
    grep -EHn "$full_user@$full_domain" "$file" 2>/dev/null | sed 's/^/  [Full] /' | tee -a "$LOG_FILE"

    # Print context for short-domain matches
    grep -EHn "$short_user@$short_domain" "$file" 2>/dev/null | sed 's/^/  [Short] /' | tee -a "$LOG_FILE"

    # Print context for internal AD / email / DC patterns
    grep -EHn "$previous_internal_ad_domain|@$previous_external_email_domain|$old_dc_dn" "$file" 2>/dev/null | sed 's/^/  [Domain/DC] /' | tee -a "$LOG_FILE"

  else
    echo "✏️ Modifying: $file" >> "$LOG_FILE"
    cp "$file" "$file.bak"
    sed -i "${sed_args[@]}" "$file"
  fi
done < <(find "$SCRIPT_BASE" -type f -print0)
echo "✅ Full details in $LOG_FILE"
fi

if [[ -n "$backup_script" && -f "$backup_script" ]]; then
  echo "📦 Updating NFS IPs in $backup_script"
  if [[ -z "$nfs_ip2" ]]; then
    new_nfs_line="DISK_OPTIONS=(\"$nfs_ip1:/backup\" \"192.168.7.115:/backup\")"
  else
    new_nfs_line="DISK_OPTIONS=(\"$nfs_ip1:/backup\" \"$nfs_ip2:/backup\")"
  fi
  sed -i -E "s|^DISK_OPTIONS=\(.*\)|$new_nfs_line|" "$backup_script"
fi

if [[ "$update_script_base" =~ ^[Yy]$ && -n "$new_script_base"  ]]; then
  echo "📁 Updating SCRIPT_BASE to: $new_script_base"

  # Derive ROOT_DIR from the new SCRIPT_BASE (one level up)
  new_root_dir="$(dirname "$new_script_base")"

  # Update SCRIPT_BASE in all launcher files
  escaped_base=$(printf '%s\n' "$new_script_base" | sed 's/[&/]/\\&/g')
  grep -rl 'SCRIPT_BASE=' "$LAUNCHER_FILE" "$SCRIPT_BASE" 2>/dev/null | while read -r file; do
    sed -i -E "s|SCRIPT_BASE=\"[^\"]+\"|SCRIPT_BASE=\"$escaped_base\"|" "$file"
    cp -R $ROOT_DIR $new_root_dir
    echo "✏️ Updated SCRIPT_BASE in $file" >> "$LOG_FILE"
    echo "📂 New ROOT_DIR will be: $new_root_dir"
    echo "📂 Consider to delete the old $ROOT_DIR directory"
  done
fi

echo "✅ Done!"
echo "If this script was useful, consider giving it a ⭐ on GitHub:"
echo "👉 https://github.com/Aviel-Amitay/it_apps"