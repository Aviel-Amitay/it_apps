#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Defaults
###############################################################################
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-il-central-1}"
SCRIPT_NAME="$(basename "$0")"
JSON_OUTPUT="no"
CREATE_KEY_ONLY="no"
CREATE_SG_ONLY="no"
REGION_FORWARDED="no"
FORWARDED_VPC_ID=""

DEFAULT_OFFICE_CIDR="172.20.1.0/16"
DEFAULT_WEB_PORTS="80,443,8080,8443,3000,123"
DEFAULT_SSH_PORT="22"
KEY_OUTPUT_DIR="${HOME}/.ssh"

###############################################################################
# Logging
###############################################################################
log() {
  printf '[INFO] %s\n' "$*" >&2
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

###############################################################################
# Help
###############################################################################
usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  -p, --profile NAME   AWS CLI profile to use (default: ${AWS_PROFILE})
  -r, --region  NAME   AWS region to use (default: ${AWS_REGION})
      --vpc-id ID      Use this VPC directly for delegated security group creation
      --create-sg      Jump directly to security group creation
      --create-key     Jump directly to key pair creation
      --json           Print machine-readable JSON for delegated flows
  -h, --help           Show this help

What this script can do:
  1. Security Groups:
     - List
     - Create
     - Modify
     - Attach to EC2 instance

  2. EC2 Key Pairs:
     - List existing keys
     - Create a new key pair
     - Ask for PEM / PPK preference

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --profile mylab --region il-central-1
EOF
}

###############################################################################
# Basic helpers
###############################################################################
require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

aws_cli() {
  aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

prompt_with_default() {
  local __var_name="$1"
  local __prompt="$2"
  local __default="$3"
  local __input

  read -r -p "$__prompt [$__default]: " __input
  __input="${__input:-$__default}"
  printf -v "$__var_name" '%s' "$__input"
}

prompt_required() {
  local __var_name="$1"
  local __prompt="$2"
  local __input

  while true; do
    read -r -p "$__prompt: " __input
    if [[ -n "$__input" ]]; then
      printf -v "$__var_name" '%s' "$__input"
      return 0
    fi
    echo "Value is required." >&2
  done
}

prompt_yes_no() {
  local __var_name="$1"
  local __prompt="$2"
  local __default="$3"
  local __input
  local __input_lc

  while true; do
    read -r -p "$__prompt [$__default]: " __input
    __input="${__input:-$__default}"
    __input_lc="$(printf '%s' "$__input" | tr '[:upper:]' '[:lower:]')"

    case "$__input_lc" in
      y|yes)
        printf -v "$__var_name" '%s' "yes"
        return 0
        ;;
      n|no)
        printf -v "$__var_name" '%s' "no"
        return 0
        ;;
      *)
        echo "Please enter yes or no." >&2
        ;;
    esac
  done
}

prompt_menu() {
  local __var_name="$1"
  local __prompt="$2"
  shift 2
  local __options=("$@")
  local __input

  while true; do
    echo >&2
    echo "$__prompt" >&2
    local i=1
    for opt in "${__options[@]}"; do
      echo "  $i) $opt" >&2
      i=$((i+1))
    done
    read -r -p "Choose an option: " __input
    if [[ "$__input" =~ ^[0-9]+$ ]] && (( __input >= 1 && __input <= ${#__options[@]} )); then
      printf -v "$__var_name" '%s' "${__options[$((__input-1))]}"
      return 0
    fi
    echo "Invalid selection." >&2
  done
}

###############################################################################
# Region helpers
###############################################################################
get_regions() {
  aws_cli ec2 describe-regions --query 'Regions[].RegionName' --output text
}

print_regions() {
  local region="$1"
  log "Available AWS regions:"
  get_regions | tr '\t' '\n' | sed 's/^/  - /'
}

prompt_region_selection() {
  local region_lines=()
  local line
  local choice
  local idx=1

  while IFS= read -r line; do
    [[ -n "$line" ]] && region_lines+=("$line")
  done < <(get_regions | tr '\t' '\n')

  [[ "${#region_lines[@]}" -gt 0 ]] || die "No AWS regions returned for profile $AWS_PROFILE"

  echo
  echo "Available AWS regions:"
  for line in "${region_lines[@]}"; do
    if [[ "$line" == "$AWS_REGION" ]]; then
      echo "  $idx) $line (default)"
    else
      echo "  $idx) $line"
    fi
    idx=$((idx+1))
  done
  echo

  while true; do
    read -r -p "Choose region number [default: $AWS_REGION]: " choice
    if [[ -z "$choice" ]]; then
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#region_lines[@]} )); then
      AWS_REGION="${region_lines[$((choice-1))]}"
      return 0
    fi
    echo "Invalid selection."
  done
}


###############################################################################
# VPC / EC2 discovery
###############################################################################
list_vpcs() {
  aws_cli ec2 describe-vpcs \
    --query 'Vpcs[*].{VpcId:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table
}

prompt_vpc_id() {
  local vpc_lines=()
  local line
  local choice
  local idx=1

  mapfile -t vpc_lines < <(
    aws_cli ec2 describe-vpcs \
      --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`]|[0].Value]' \
      --output text
  )

  [[ "${#vpc_lines[@]}" -gt 0 ]] || die "No VPCs found in region $AWS_REGION"

  echo
  echo "Available VPCs:"
  for line in "${vpc_lines[@]}"; do
    local vpc_id cidr name
    vpc_id="$(awk '{print $1}' <<< "$line")"
    cidr="$(awk '{print $2}' <<< "$line")"
    name="$(awk '{print $3}' <<< "$line")"
    [[ -z "$name" || "$name" == "None" ]] && name="N/A"

    echo "  $idx) Name=$name | VpcId=$vpc_id | CIDR=$cidr"
    idx=$((idx+1))
  done
  echo

  while true; do
    read -r -p "Choose VPC number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#vpc_lines[@]} )); then
      SELECTED_VPC_ID="$(awk '{print $1}' <<< "${vpc_lines[$((choice-1))]}")"
      return 0
    fi
    echo "Invalid selection."
  done
}

prompt_instance_id() {
  echo
  echo "Available EC2 instances:"
  list_instances
  echo
  prompt_required SELECTED_INSTANCE_ID "Enter Instance ID"
}

get_primary_eni_id() {
  local instance_id="$1"

  aws_cli ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==`0`].NetworkInterfaceId | [0]' \
    --output text
}

###############################################################################
# Security Groups
###############################################################################
prompt_vpc_id() {
  local vpc_lines=()
  local line
  local choice
  local idx=1

  while IFS= read -r line; do
    [[ -n "$line" ]] && vpc_lines+=("$line")
  done < <(
    aws_cli ec2 describe-vpcs \
      --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`]|[0].Value]' \
      --output text
  )

  [[ "${#vpc_lines[@]}" -gt 0 ]] || die "No VPCs found in region $AWS_REGION"

  echo
  echo "Available VPCs:"
  for line in "${vpc_lines[@]}"; do
    local vpc_id cidr name
    vpc_id="$(awk '{print $1}' <<< "$line")"
    cidr="$(awk '{print $2}' <<< "$line")"
    name="$(awk '{print $3}' <<< "$line")"
    [[ -z "$name" || "$name" == "None" ]] && name="N/A"

    echo "  $idx) VPC name: $name | VPC ID: $vpc_id | CIDR: $cidr"
    idx=$((idx+1))
  done
  echo

  while true; do
    read -r -p "Choose VPC number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#vpc_lines[@]} )); then
      SELECTED_VPC_ID="$(awk '{print $1}' <<< "${vpc_lines[$((choice-1))]}")"
      return 0
    fi
    echo "Invalid selection."
  done
}

prompt_security_group_id() {
  local vpc_id="$1"
  local sg_lines=()
  local line
  local choice
  local idx=1

  while IFS= read -r line; do
    [[ -n "$line" ]] && sg_lines+=("$line")
  done < <(
    aws_cli ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
      --output text
  )

  [[ "${#sg_lines[@]}" -gt 0 ]] || die "No security groups found in VPC $vpc_id"

  echo
  echo "Available security groups:"
  for line in "${sg_lines[@]}"; do
    local sg_id sg_name sg_desc
    sg_id="$(awk '{print $1}' <<< "$line")"
    sg_name="$(awk '{print $2}' <<< "$line")"
    sg_desc="$(cut -d' ' -f3- <<< "$line")"
    [[ -z "$sg_name" || "$sg_name" == "None" ]] && sg_name="N/A"

    echo "  $idx) Name: $sg_name | GroupId: $sg_id | Description: $sg_desc"
    idx=$((idx+1))
  done
  echo

  while true; do
    read -r -p "Choose security group number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#sg_lines[@]} )); then
      SELECTED_SG_ID="$(awk '{print $1}' <<< "${sg_lines[$((choice-1))]}")"
      return 0
    fi
    echo "Invalid selection."
  done
}

show_security_group_details() {
  local sg_id="$1"

  echo
  echo "=================================================="
  echo "Security Group Summary"
  echo "=================================================="

  aws_cli ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query 'SecurityGroups[0].{GroupId:GroupId,GroupName:GroupName,Description:Description,VpcId:VpcId}' \
    --output table

  echo
  echo "Inbound rules - Ingress rules: (e.g.Traffic allowed to reach instances with this security group):"
  aws_cli ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query 'SecurityGroups[0].IpPermissions[*].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,IpRanges:IpRanges[*].CidrIp}' \
    --output table

  echo
  echo "Outbound rules - Egress rules: (e.g. Traffic allowed to leave instances with this security group):"
  aws_cli ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query 'SecurityGroups[0].IpPermissionsEgress[*].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,IpRanges:IpRanges[*].CidrIp}' \
    --output table
  echo
}

list_security_groups() {
  local vpc_id="$1"

  aws_cli ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query 'SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,Description:Description}' \
    --output table
}

create_security_group() {
  local vpc_id="$1"
  local sg_name="$2"
  local sg_desc="$3"

  aws_cli ec2 create-security-group \
    --group-name "$sg_name" \
    --description "$sg_desc" \
    --vpc-id "$vpc_id" \
    --query 'GroupId' \
    --output text
}

add_ingress_rule_simple() {
  local sg_id="$1"
  local protocol="$2"
  local port="$3"
  local cidr="$4"

  aws_cli ec2 authorize-security-group-ingress \
    --group-id "$sg_id" \
    --ip-permissions "IpProtocol=${protocol},FromPort=${port},ToPort=${port},IpRanges=[{CidrIp=${cidr}}]" \
    >/dev/null
}

add_ingress_rule_port_range() {
  local sg_id="$1"
  local protocol="$2"
  local from_port="$3"
  local to_port="$4"
  local cidr="$5"

  aws_cli ec2 authorize-security-group-ingress \
    --group-id "$sg_id" \
    --ip-permissions "IpProtocol=${protocol},FromPort=${from_port},ToPort=${to_port},IpRanges=[{CidrIp=${cidr}}]" \
    >/dev/null
}

prompt_sg_profile_and_apply() {
  local sg_id="$1"

  local profile_choice
  local office_rule_choice
  local cidr
  local port
  local from_port
  local to_port

  prompt_menu profile_choice "Choose security group rule type" \
    "SSH (22)" \
    "Web/App ports (80,443,8080,8443,3000,123)" \
    "Office CIDR (${DEFAULT_OFFICE_CIDR})" \
    "Custom port + custom IP/CIDR"

  case "$profile_choice" in
    "SSH (22)")
      prompt_with_default cidr "Allowed CIDR for SSH" "0.0.0.0/0"
      add_ingress_rule_simple "$sg_id" "tcp" "22" "$cidr"
      log "Added SSH rule to $sg_id"
      ;;
    "Web/App ports (80,443,8080,8443,3000,123)")
      prompt_with_default cidr "Allowed CIDR for web/app ports" "0.0.0.0/0"
      IFS=',' read -r -a ports <<< "$DEFAULT_WEB_PORTS"
      for port in "${ports[@]}"; do
        add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
      done
      log "Added web/app rules to $sg_id"
      ;;
    "Office CIDR (${DEFAULT_OFFICE_CIDR})")
      prompt_with_default cidr "Office CIDR" "$DEFAULT_OFFICE_CIDR"
      prompt_menu office_rule_choice "Choose office rule type" \
        "SSH only (22)" \
        "Web/App ports (${DEFAULT_WEB_PORTS})" \
        "Custom single port" \
        "Custom port range"

      case "$office_rule_choice" in
        "SSH only (22)")
          add_ingress_rule_simple "$sg_id" "tcp" "22" "$cidr"
          ;;
        "Web/App ports (${DEFAULT_WEB_PORTS})")
          IFS=',' read -r -a ports <<< "$DEFAULT_WEB_PORTS"
          for port in "${ports[@]}"; do
            add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
          done
          ;;
        "Custom single port")
          prompt_required port "Enter port"
          add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
          ;;
        "Custom port range")
          prompt_required from_port "Enter start port"
          prompt_required to_port "Enter end port"
          add_ingress_rule_port_range "$sg_id" "tcp" "$from_port" "$to_port" "$cidr"
          ;;
      esac
      log "Added office rule(s) to $sg_id"
      ;;
    "Custom port + custom IP/CIDR")
      prompt_required port "Enter single port"
      prompt_required cidr "Enter IP or CIDR (example 192.168.1.10/32 or 172.20.1.0/16)"
      add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
      log "Added custom rule to $sg_id"
      ;;
  esac
}

modify_existing_security_group() {
  local vpc_id="$1"
  local action
  local predefined_choice
  local cidr
  local port

  prompt_security_group_id "$vpc_id"
  local sg_id="$SELECTED_SG_ID"

  show_security_group_details "$sg_id"

  while true; do
    prompt_menu action "What do you want to do with security group $sg_id?" \
      "Add predefined rule" \
      "Add custom rule" \
      "Show security group details again" \
      "Back"

    case "$action" in
      "Add predefined rule")
        prompt_menu predefined_choice "Choose predefined rule type" \
          "SSH (22)" \
          "Web/App ports (80,443,8080,8443,3000,123)" \
          "Office CIDR (${DEFAULT_OFFICE_CIDR})"

        case "$predefined_choice" in
          "SSH (22)")
            prompt_with_default cidr "Allowed CIDR for SSH" "0.0.0.0/0"
            add_ingress_rule_simple "$sg_id" "tcp" "22" "$cidr"
            log "Added SSH rule to $sg_id"
            ;;
          "Web/App ports (80,443,8080,8443,3000,123)")
            prompt_with_default cidr "Allowed CIDR for web/app ports" "0.0.0.0/0"
            IFS=',' read -r -a ports <<< "$DEFAULT_WEB_PORTS"
            for port in "${ports[@]}"; do
              add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
            done
            log "Added web/app rules to $sg_id"
            ;;
          "Office CIDR (${DEFAULT_OFFICE_CIDR})")
            prompt_with_default cidr "Office CIDR" "$DEFAULT_OFFICE_CIDR"
            prompt_required port "Enter port"
            add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
            log "Added office rule to $sg_id"
            ;;
        esac
        ;;
      "Add custom rule")
        prompt_required port "Enter single port"
        prompt_required cidr "Enter IP or CIDR"
        add_ingress_rule_simple "$sg_id" "tcp" "$port" "$cidr"
        log "Added custom rule to $sg_id"
        ;;
      "Show security group details again")
        show_security_group_details "$sg_id"
        ;;
      "Back")
        return 0
        ;;
    esac
  done
}

create_new_security_group_workflow() {
  local vpc_id="$1"
  local sg_name
  local sg_desc
  local sg_id

  prompt_required sg_name "Enter new security group name"
  prompt_with_default sg_desc "Enter security group description" "Managed by script"

  sg_id="$(create_security_group "$vpc_id" "$sg_name" "$sg_desc")"
  log "Created Security Group: $sg_id"

  prompt_sg_profile_and_apply "$sg_id"

  if [[ "$JSON_OUTPUT" == "yes" ]]; then
    printf '{"security_group_id":"%s","group_id":"%s","group_name":"%s","vpc_id":"%s","region":"%s"}\n' \
      "$sg_id" "$sg_id" "$sg_name" "$vpc_id" "$AWS_REGION"
    return 0
  fi

  echo
  echo "Created security group:"
  aws_cli ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query 'SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,Description:Description}' \
    --output table

  show_security_group_details "$sg_id"
}

attach_security_group_to_instance() {
  local vpc_id="$1"
  local instance_id
  local eni_id
  local attach_choice
  local sg_id
  local new_sg_name
  local new_sg_desc
  local current_groups
  local combined_groups

  prompt_instance_id
  instance_id="$SELECTED_INSTANCE_ID"

  eni_id="$(get_primary_eni_id "$instance_id")"
  [[ -n "$eni_id" && "$eni_id" != "None" ]] || die "Could not find primary ENI for instance $instance_id"

  echo
  echo "Security groups available in VPC $vpc_id:"
  list_security_groups "$vpc_id"
  echo

  prompt_menu attach_choice "What do you want to attach?" \
    "Use existing security group" \
    "Create new security group and attach it"

  case "$attach_choice" in
    "Use existing security group")
      prompt_security_group_id "$vpc_id"
      sg_id="$SELECTED_SG_ID"
      show_security_group_details "$sg_id"
      ;;
    "Create new security group and attach it")
      prompt_required new_sg_name "Enter new security group name"
      prompt_with_default new_sg_desc "Enter security group description" "Managed by script"
      sg_id="$(create_security_group "$vpc_id" "$new_sg_name" "$new_sg_desc")"
      log "Created Security Group: $sg_id"
      prompt_sg_profile_and_apply "$sg_id"
      show_security_group_details "$sg_id"
      ;;
  esac

  current_groups="$(aws_cli ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].Groups[].GroupId' \
    --output text)"

  combined_groups="$(printf '%s\n%s\n' "$current_groups" "$sg_id" | tr '\t' '\n' | awk 'NF' | awk '!seen[$0]++' | xargs)"
  [[ -n "$combined_groups" ]] || die "No security groups to apply"

  aws_cli ec2 modify-network-interface-attribute \
    --network-interface-id "$eni_id" \
    --groups $combined_groups

  log "Attached security group $sg_id to instance $instance_id via ENI $eni_id"
}

delete_security_group() {
  local vpc_id="$1"
  local sg_id
  local confirm_delete

  prompt_security_group_id "$vpc_id"
  sg_id="$SELECTED_SG_ID"

  show_security_group_details "$sg_id"
  prompt_yes_no confirm_delete "Delete security group $sg_id?" "no"

  if [[ "$confirm_delete" != "yes" ]]; then
    log "Deletion cancelled for security group $sg_id"
    return 0
  fi

  aws_cli ec2 delete-security-group \
    --group-id "$sg_id"

  log "Deleted security group $sg_id"
}

security_group_main_menu() {
  local vpc_id
  local action
  local inspect_now

  prompt_vpc_id
  vpc_id="$SELECTED_VPC_ID"

  while true; do
    prompt_menu action "Security Group menu for VPC $vpc_id" \
      "List security groups" \
      "Create new security group" \
      "Modify existing security group" \
      "Attach security group to EC2" \
      "Delete security group" \
      "Back to main menu"

    case "$action" in
      "List security groups")
        list_security_groups "$vpc_id"
        prompt_yes_no inspect_now "Do you want to inspect one security group now?" "yes"
        if [[ "$inspect_now" == "yes" ]]; then
          prompt_security_group_id "$vpc_id"
          show_security_group_details "$SELECTED_SG_ID"
        fi
        ;;
      "Create new security group")
        create_new_security_group_workflow "$vpc_id"
        ;;
      "Modify existing security group")
        modify_existing_security_group "$vpc_id"
        ;;
      "Attach security group to EC2")
        attach_security_group_to_instance "$vpc_id"
        ;;
      "Delete security group")
        delete_security_group "$vpc_id"
        ;;
      "Back to main menu")
        return 0
        ;;
    esac
  done
}

###############################################################################
# Key pairs
###############################################################################
list_key_pairs() {
  aws_cli ec2 describe-key-pairs \
    --query 'KeyPairs[*].{KeyName:KeyName,KeyType:KeyType,Fingerprint:KeyFingerprint}' \
    --output table
}

create_key_pair_workflow() {
  local key_name
  local key_type_choice
  local output_file
  local pem_file
  local aws_key_name

  mkdir -p "$KEY_OUTPUT_DIR"
  chmod 700 "$KEY_OUTPUT_DIR" || true

  prompt_required key_name "Enter key pair name"

  prompt_menu key_type_choice "Choose key type" \
    "pem" \
    "ppk"

  case "$key_type_choice" in
    "pem")
      aws_key_name="aws-$(date +%Y-%m-%d)-${AWS_REGION}-${key_name}"
      output_file="${KEY_OUTPUT_DIR}/${aws_key_name}.pem"
      aws_cli ec2 create-key-pair \
        --key-name "$aws_key_name" \
        --query 'KeyMaterial' \
        --output text > "$output_file"
      chmod 600 "$output_file"
      log "Created key pair $aws_key_name"
      if [[ "$JSON_OUTPUT" == "yes" ]]; then
        printf '{"key_name":"%s","key_type":"pem","output_file":"%s","region":"%s"}\n' \
          "$aws_key_name" "$output_file" "$AWS_REGION"
      else
        echo "Saved private key to: $output_file"
      fi
      ;;
    "ppk")
      aws_key_name="$key_name"
      pem_file="${KEY_OUTPUT_DIR}/aws-$(date +%Y-%m-%d)-${key_name}.pem"
      aws_cli ec2 create-key-pair \
        --key-name "$aws_key_name" \
        --query 'KeyMaterial' \
        --output text > "$pem_file"
      chmod 600 "$pem_file"
      log "Created key pair $aws_key_name"
      if [[ "$JSON_OUTPUT" == "yes" ]]; then
        printf '{"key_name":"%s","key_type":"ppk","output_file":"%s","region":"%s"}\n' \
          "$aws_key_name" "$pem_file" "$AWS_REGION"
      else
        echo "AWS CLI saved the private key as PEM: $pem_file"
        echo "To use PPK, convert the PEM file with PuTTYgen."
      fi
      ;;
  esac
}

delete_key_pair_workflow() {
  local key_lines=()
  local line
  local choice
  local idx=1
  local key_name
  local confirm_delete
  local pem_file

  while IFS= read -r line; do
    [[ -n "$line" ]] && key_lines+=("$line")
  done < <(
    aws_cli ec2 describe-key-pairs \
      --query 'KeyPairs[*].[KeyName,KeyType,KeyFingerprint]' \
      --output text
  )

  [[ "${#key_lines[@]}" -gt 0 ]] || die "No key pairs found in region $AWS_REGION"


  echo
  echo "Available key pairs:"
  printf "  %-3s %-30s %-12s\n" "No." "KeyName" "KeyType"
  printf "  %-3s %-30s %-12s\n" "---" "------------------------------" "------------"

  for line in "${key_lines[@]}"; do
    local list_key_name list_key_type
    list_key_name="$(awk '{print $1}' <<< "$line")"
    list_key_type="$(awk '{print $2}' <<< "$line")"

    printf "  %-3s %-30s %-12s\n" "$idx)" "$list_key_name" "$list_key_type"
    idx=$((idx+1))
  done
  echo
 
  while true; do
    read -r -p "Choose key pair number to delete: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#key_lines[@]} )); then
      key_name="$(awk '{print $1}' <<< "${key_lines[$((choice-1))]}")"
      break
    fi
    echo "Invalid selection."
  done

  echo
  echo "Selected key pair:"
  aws_cli ec2 describe-key-pairs \
    --key-names "$key_name" \
    --query 'KeyPairs[0].{KeyName:KeyName,KeyType:KeyType,Fingerprint:KeyFingerprint}' \
    --output table

  prompt_yes_no confirm_delete "Are you sure you want to delete key pair $key_name?" "no"
  if [[ "$confirm_delete" != "yes" ]]; then
    log "Deletion cancelled for key pair $key_name"
    return 0
  fi

  aws_cli ec2 delete-key-pair \
    --key-name "$key_name"

  log "Deleted key pair $key_name"
  echo ""

  pem_file="$(ls "${KEY_OUTPUT_DIR}"/*"${key_name}"*.pem 2>/dev/null | head -n1)"

  echo ""
  echo "Deleted key pair $key_name from AWS. Now checking for local PEM file to remove..."
  echo "Expected local PEM file path: $pem_file"
  echo ""

  if [[ -f "$pem_file" ]]; then
    rm -f "$pem_file"
    log "Removed local PEM file: $pem_file"
  else
    log "No local PEM file found for $key_name"
  fi
}

key_pair_main_menu() {
  local action

  while true; do
    prompt_menu action "Key pair menu" \
      "List existing key pairs" \
      "Create a new SSH key pair" \
      "Delete SSH key pair" \
      "Back to main menu"

    case "$action" in
      "List existing key pairs")
        list_key_pairs
        prompt_menu after_list "Next action" \
          "Create new key pair" \
          "Back to key pair menu"
        case "$after_list" in
          "Create new key pair")
            create_key_pair_workflow
            ;;
          "Back to key pair menu")
            ;;
        esac
        ;;
      "Create a new SSH key pair")
        create_key_pair_workflow
        ;;
      "Delete SSH key pair")
        delete_key_pair_workflow
        ;;
      "Back to main menu")
        return 0
        ;;
    esac
  done
}

###############################################################################
# Main menu
###############################################################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--profile)
        [[ $# -lt 2 ]] && die "Missing value for $1"
        AWS_PROFILE="$2"
        shift 2
        ;;
      -r|--region)
        [[ $# -lt 2 ]] && die "Missing value for $1"
        AWS_REGION="$2"
        REGION_FORWARDED="yes"
        shift 2
        ;;
      --vpc-id)
        [[ $# -lt 2 ]] && die "Missing value for $1"
        FORWARDED_VPC_ID="$2"
        shift 2
        ;;
      --create-sg)
        CREATE_SG_ONLY="yes"
        shift
        ;;
      --create-key)
        CREATE_KEY_ONLY="yes"
        shift
        ;;
      --json)
        JSON_OUTPUT="yes"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  require_command aws
  require_command awk
  require_command xargs
  require_command tr

  if [[ "$CREATE_SG_ONLY" == "yes" ]]; then
    log "Using AWS profile: $AWS_PROFILE"
    log "Using AWS region : $AWS_REGION"
    if [[ -z "$FORWARDED_VPC_ID" ]]; then
      prompt_vpc_id
      FORWARDED_VPC_ID="$SELECTED_VPC_ID"
    fi
    create_new_security_group_workflow "$FORWARDED_VPC_ID"
    exit 0
  fi

  if [[ "$CREATE_KEY_ONLY" == "yes" ]]; then
    log "Using AWS profile: $AWS_PROFILE"
    log "Using AWS region : $AWS_REGION"
    create_key_pair_workflow
    exit 0
  fi

  if [[ "$REGION_FORWARDED" == "yes" ]]; then
    log "Using forwarded region: $AWS_REGION"
  else
    prompt_region_selection
  fi

  log "Using AWS profile: $AWS_PROFILE"
  log "Using AWS region : $AWS_REGION"

  local main_action

  while true; do
    prompt_menu main_action "Main menu" \
      "Manage security groups" \
      "Manage SSH key pairs" \
      "Exit"

    case "$main_action" in
      "Manage security groups")
        security_group_main_menu
        ;;
      "Manage SSH key pairs")
        key_pair_main_menu
        ;;
      "Exit")
        log "Exiting."
        exit 0
        ;;
    esac
  done
}

main "$@"
