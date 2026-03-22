#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# EC2 launcher/orchestrator
#
# Purpose:
#   - use existing AWS resources when given via short flags
#   - delegate resource creation via long flags to external scripts
#   - fall back to interactive selection when values are missing
#
# Notes:
#   - this script does NOT create VPC / SG / key / subnet directly
#   - it calls dedicated scripts you already have
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

################################
# Defaults
################################
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
: "${AWS_REGION:=us-east-1}"

# Existing resource / runtime inputs
VPC_ID=""
SUBNET_ID=""
SG_ID=""
KEY_NAME=""
OS_NAME=""
INSTANCE_TYPE=""
ROOT_DISK_SIZE=""
DATA_DISK_SIZE=""
USER_DATA_FILE=""
INSTANCE_NAME=""

# Optional behavior
NON_INTERACTIVE=false
DRY_RUN=false

# Delegated creation flags
CREATE_VPC=false
CREATE_SUBNET=false
CREATE_SG=false
CREATE_KEY=false
CREATE_ALL_MISSING=false

# Resolved at runtime
AMI_ID=""
ADD_EXTRA_DISK=false

################################
# Helpers
################################
have() {
  command -v "$1" >/dev/null 2>&1
}

info() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    echo
    return 0
  fi
  "$@"
}

usage() {
  cat <<'EOF'
Usage:
  manage_ec2_instance.sh [options]

Existing resources / values:
  -R, --region REGION
  -v, --vpc-id VPC_ID
  -u, --subnet-id SUBNET_ID
  -s, --sg-id SG_ID
  -k, --key-name KEY_NAME
  -o, --os OS_NAME
  -t, --instance-type TYPE
  -r, --root-disk SIZE_GB
  -d, --data-disk SIZE_GB
  -f, --user-data-file FILE
  -n, --name INSTANCE_NAME

Delegated creation flags:
      --create-vpc
      --create-subnet
      --create-sg
      --create-key
      --create-all-missing

General:
      --non-interactive
      --dry-run
  -h, --help

Examples:
  Use existing resources:
    ./manage_ec2_instance.sh \
      -R eu-central-1 \
      -v vpc-12345678 \
      -u subnet-12345678 \
      -s sg-12345678 \
      -k my-key \
      -o ubuntu \
      -t t3.micro \
      -r 30 \
      -d 100 \
      -n my-server

  Delegate missing resource creation:
    ./manage_ec2_instance.sh \
      -R eu-central-1 \
      -v vpc-12345678 \
      --create-subnet \
      --create-sg \
      --create-key \
      -o amazonlinux \
      -t t3.small \
      -r 20 \
      -n web01

Supported OS values:
  amazonlinux
  ubuntu
  rhel
  fedora
  windows
EOF
}

parse_args() {
  local parsed
  parsed="$(getopt \
    --options R:v:u:s:k:o:t:r:d:f:n:h \
    --longoptions region:,vpc-id:,subnet-id:,sg-id:,key-name:,os:,instance-type:,root-disk:,data-disk:,user-data-file:,name:,create-vpc,create-subnet,create-sg,create-key,create-all-missing,non-interactive,dry-run,help \
    --name "$0" -- "$@")" || exit 1

  eval set -- "$parsed"

  while true; do
    case "$1" in
      -R|--region) AWS_REGION="$2"; shift 2 ;;
      -v|--vpc-id) VPC_ID="$2"; shift 2 ;;
      -u|--subnet-id) SUBNET_ID="$2"; shift 2 ;;
      -s|--sg-id) SG_ID="$2"; shift 2 ;;
      -k|--key-name) KEY_NAME="$2"; shift 2 ;;
      -o|--os) OS_NAME="$2"; shift 2 ;;
      -t|--instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
      -r|--root-disk) ROOT_DISK_SIZE="$2"; shift 2 ;;
      -d|--data-disk) DATA_DISK_SIZE="$2"; shift 2 ;;
      -f|--user-data-file) USER_DATA_FILE="$2"; shift 2 ;;
      -n|--name) INSTANCE_NAME="$2"; shift 2 ;;

      --create-vpc) CREATE_VPC=true; shift ;;
      --create-subnet) CREATE_SUBNET=true; shift ;;
      --create-sg) CREATE_SG=true; shift ;;
      --create-key) CREATE_KEY=true; shift ;;
      --create-all-missing) CREATE_ALL_MISSING=true; shift ;;
      --non-interactive) NON_INTERACTIVE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      *) fail "Unexpected option: $1" ;;
    esac
  done
}

################################
# Prereq checks
################################
check_prereqs() {
  have aws || fail "aws CLI is not installed."
  have jq || fail "jq is not installed."
  have getopt || fail "getopt is not installed."

  if [[ "$DRY_RUN" == false ]]; then
    aws sts get-caller-identity --output json >/dev/null \
      || fail "AWS CLI is not authenticated or permissions are missing."
  fi

  info "AWS default/configured region: ${AWS_REGION:-none}"
}

################################
# Basic validators
################################
validate_numeric_gib() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$label must be numeric."
  (( value > 0 )) || fail "$label must be greater than 0."
}

validate_user_data_file() {
  [[ -n "$USER_DATA_FILE" ]] || return 0
  [[ -f "$USER_DATA_FILE" ]] || fail "User-data file not found: $USER_DATA_FILE"
}

validate_os_name() {
  case "$OS_NAME" in
    amazonlinux|ubuntu|rhel|fedora|windows) ;;
    *) fail "Unsupported OS '$OS_NAME'. Use: amazonlinux | ubuntu | rhel | fedora | windows" ;;
  esac
}

validate_vpc_exists() {
  [[ -n "$VPC_ID" ]] || fail "validate_vpc_exists called with empty VPC_ID"
  [[ "$DRY_RUN" == true ]] && return 0

  aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --vpc-ids "$VPC_ID" \
    --output json >/dev/null \
    || fail "VPC not found: $VPC_ID"
}

validate_subnet_exists() {
  [[ -n "$SUBNET_ID" ]] || fail "validate_subnet_exists called with empty SUBNET_ID"
  [[ "$DRY_RUN" == true ]] && return 0

  aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --subnet-ids "$SUBNET_ID" \
    --output json >/dev/null \
    || fail "Subnet not found: $SUBNET_ID"
}

validate_sg_exists() {
  [[ -n "$SG_ID" ]] || fail "validate_sg_exists called with empty SG_ID"
  [[ "$DRY_RUN" == true ]] && return 0

  aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --group-ids "$SG_ID" \
    --output json >/dev/null \
    || fail "Security Group not found: $SG_ID"
}

validate_key_exists() {
  [[ -n "$KEY_NAME" ]] || fail "validate_key_exists called with empty KEY_NAME"
  [[ "$DRY_RUN" == true ]] && return 0

  aws ec2 describe-key-pairs \
    --region "$AWS_REGION" \
    --key-names "$KEY_NAME" \
    --output json >/dev/null \
    || fail "Key Pair not found: $KEY_NAME"
}

validate_subnet_in_vpc() {
  [[ -n "$VPC_ID" && -n "$SUBNET_ID" ]] || return 0
  [[ "$DRY_RUN" == true ]] && return 0

  local subnet_vpc
  subnet_vpc="$(aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --subnet-ids "$SUBNET_ID" \
    --query 'Subnets[0].VpcId' \
    --output text)"

  [[ "$subnet_vpc" == "$VPC_ID" ]] || fail "Subnet $SUBNET_ID does not belong to VPC $VPC_ID"
}

validate_sg_in_vpc() {
  [[ -n "$VPC_ID" && -n "$SG_ID" ]] || return 0
  [[ "$DRY_RUN" == true ]] && return 0

  local sg_vpc
  sg_vpc="$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].VpcId' \
    --output text)"

  [[ "$sg_vpc" == "$VPC_ID" ]] || fail "Security Group $SG_ID does not belong to VPC $VPC_ID"
}

################################
# Interactive helpers
################################
prompt_non_empty() {
  local label="$1"
  local value=""
  while true; do
    read -r -p "$label" value
    [[ -n "$value" ]] && { echo "$value"; return 0; }
    echo "Value cannot be empty."
  done
}

choose_vpc_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing VPC. Use -v/--vpc-id or --create-vpc"

  local data count choice
  data="$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Name: join(``, Tags[?Key==`Name`].Value) || `NoName`}' \
    --output json | jq 'sort_by(.Name, .VpcId)')"

  count="$(echo "$data" | jq 'length')"
  if (( count == 0 )); then
  warn "No VPCs found in region $AWS_REGION"

  PS3="Choose action: "
  select action in "Change region" "Create VPC" "Exit"; do
    case "$REPLY" in
      1) choose_region_interactively; choose_vpc_interactively; return ;;
      2) create_vpc_via_external_script; return ;;
      3) fail "No VPCs found";;
    esac
  done
fi

  echo
  echo "==== Select VPC ===="
  for ((i=0; i<count; i++)); do
    printf "%2d) %s [%s | %s]\n" \
      "$((i+1))" \
      "$(echo "$data" | jq -r ".[$i].Name")" \
      "$(echo "$data" | jq -r ".[$i].VpcId")" \
      "$(echo "$data" | jq -r ".[$i].Cidr")"
  done

  while true; do
    read -r -p "Choose VPC 1-$count: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      VPC_ID="$(echo "$data" | jq -r ".[$((choice-1))].VpcId")"
      return 0
    fi
    echo "Invalid selection."
  done
}

choose_subnet_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing Subnet. Use -u/--subnet-id or --create-subnet"
  [[ -n "$VPC_ID" ]] || fail "Cannot choose subnet without VPC_ID"

  local data count choice
  data="$(aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].{SubnetId:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,Name: join(``, Tags[?Key==`Name`].Value) || `NoName`}' \
    --output json | jq 'sort_by(.Az, .Name, .SubnetId)')"

  count="$(echo "$data" | jq 'length')"
  (( count > 0 )) || fail "No subnets found in VPC $VPC_ID"

  echo
  echo "==== Select Subnet ===="
  for ((i=0; i<count; i++)); do
    printf "%2d) %s [%s | %s | %s]\n" \
      "$((i+1))" \
      "$(echo "$data" | jq -r ".[$i].Name")" \
      "$(echo "$data" | jq -r ".[$i].SubnetId")" \
      "$(echo "$data" | jq -r ".[$i].Az")" \
      "$(echo "$data" | jq -r ".[$i].Cidr")"
  done

  while true; do
    read -r -p "Choose Subnet 1-$count: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      SUBNET_ID="$(echo "$data" | jq -r ".[$((choice-1))].SubnetId")"
      return 0
    fi
    echo "Invalid selection."
  done
}

choose_sg_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing Security Group. Use -s/--sg-id or --create-sg"
  [[ -n "$VPC_ID" ]] || fail "Cannot choose security group without VPC_ID"

  local data count choice
  data="$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName,Desc:Description}' \
    --output json | jq 'sort_by(.Name, .GroupId)')"

  count="$(echo "$data" | jq 'length')"
  (( count > 0 )) || fail "No security groups found in VPC $VPC_ID"

  echo
  echo "==== Select Security Group ===="
  for ((i=0; i<count; i++)); do
    printf "%2d) %s [%s] - %s\n" \
      "$((i+1))" \
      "$(echo "$data" | jq -r ".[$i].Name")" \
      "$(echo "$data" | jq -r ".[$i].GroupId")" \
      "$(echo "$data" | jq -r ".[$i].Desc")"
  done

  while true; do
    read -r -p "Choose Security Group 1-$count: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      SG_ID="$(echo "$data" | jq -r ".[$((choice-1))].GroupId")"
      return 0
    fi
    echo "Invalid selection."
  done
}

choose_key_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing Key Pair. Use -k/--key-name or --create-key"

  local data count choice
  data="$(aws ec2 describe-key-pairs \
    --region "$AWS_REGION" \
    --query 'KeyPairs[].{KeyName:KeyName,KeyPairId:KeyPairId}' \
    --output json | jq 'sort_by(.KeyName)')"

  count="$(echo "$data" | jq 'length')"
  if (( count == 0 )); then
    info "No key pairs found in region $AWS_REGION. Delegating key creation to manage_aws_security.sh..."
    create_key_via_external_script
    return 0
  fi

  echo
  echo "==== Select Key Pair ===="
  for ((i=0; i<count; i++)); do
    printf "%2d) %s [%s]\n" \
      "$((i+1))" \
      "$(echo "$data" | jq -r ".[$i].KeyName")" \
      "$(echo "$data" | jq -r ".[$i].KeyPairId")"
  done

  while true; do
    read -r -p "Choose Key Pair 1-$count: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      KEY_NAME="$(echo "$data" | jq -r ".[$((choice-1))].KeyName")"
      return 0
    fi
    echo "Invalid selection."
  done
}

choose_os_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing OS. Use -o/--os"

  echo
  echo "==== Select OS ===="
  echo " 1) amazonlinux"
  echo " 2) ubuntu"
  echo " 3) rhel"
  echo " 4) fedora"
  echo " 5) windows"

  local choice
  while true; do
    read -r -p "Choose OS 1-5: " choice
    case "$choice" in
      1) OS_NAME="amazonlinux"; return 0 ;;
      2) OS_NAME="ubuntu"; return 0 ;;
      3) OS_NAME="rhel"; return 0 ;;
      4) OS_NAME="fedora"; return 0 ;;
      5) OS_NAME="windows"; return 0 ;;
      *) echo "Invalid selection." ;;
    esac
  done
}

choose_instance_type_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || fail "Missing instance type. Use -t/--instance-type"

  echo
  echo "==== Select instance type ===="
  echo " 1) t3.micro"
  echo " 2) t3.small"
  echo " 3) t3.medium"
  echo " 4) t3.large"

  local choice
  while true; do
    read -r -p "Choose 1-4: " choice
    case "$choice" in
      1) INSTANCE_TYPE="t3.micro"; return 0 ;;
      2) INSTANCE_TYPE="t3.small"; return 0 ;;
      3) INSTANCE_TYPE="t3.medium"; return 0 ;;
      4) INSTANCE_TYPE="t3.large"; return 0 ;;
      *) echo "Invalid selection." ;;
    esac
  done
}

choose_storage_interactively() {
  [[ -n "$ROOT_DISK_SIZE" ]] || ROOT_DISK_SIZE="$(prompt_non_empty 'Enter root disk size in GiB: ')"
  validate_numeric_gib "Root disk size" "$ROOT_DISK_SIZE"

  if [[ -z "$DATA_DISK_SIZE" && "$NON_INTERACTIVE" == false ]]; then
    local ans
    read -r -p "Attach extra EBS volume? (y/n): " ans
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    if [[ "$ans" == "y" ]]; then
      DATA_DISK_SIZE="$(prompt_non_empty 'Enter extra disk size in GiB: ')"
    fi
  fi

  if [[ -n "$DATA_DISK_SIZE" ]]; then
    validate_numeric_gib "Extra disk size" "$DATA_DISK_SIZE"
    ADD_EXTRA_DISK=true
  else
    ADD_EXTRA_DISK=false
  fi
}

choose_name_interactively() {
  [[ -n "$INSTANCE_NAME" ]] || INSTANCE_NAME="$(prompt_non_empty 'Enter EC2 Name tag: ')"
}

choose_user_data_interactively() {
  if [[ -n "$USER_DATA_FILE" ]]; then
    validate_user_data_file
    return 0
  fi

  [[ "$NON_INTERACTIVE" == false ]] || return 0

  echo
  echo "==== User-data ===="
  echo " 1) none"
  echo " 2) load from file"
  echo " 3) paste inline"

  local choice
  while true; do
    read -r -p "Choose 1-3: " choice
    case "$choice" in
      1)
        USER_DATA_FILE=""
        return 0
        ;;
      2)
        USER_DATA_FILE="$(prompt_non_empty 'Enter full path to user-data file: ')"
        validate_user_data_file
        return 0
        ;;
      3)
        USER_DATA_FILE="$TMP_DIR/userdata.sh"
        echo "Paste user-data, end with a single line: EOF"
        : > "$USER_DATA_FILE"
        while IFS= read -r line; do
          [[ "$line" == "EOF" ]] && break
          echo "$line" >> "$USER_DATA_FILE"
        done
        return 0
        ;;
      *)
        echo "Invalid selection."
        ;;
    esac
  done
}

################################
# Delegation hooks
################################
create_vpc_via_external_script() {
  local result summary

  info "Delegating VPC creation to build_multi_vpc.sh in region $AWS_REGION..."

  result="$("$SCRIPT_DIR/build_multi_vpc.sh" --region "$AWS_REGION")"

  summary="$(echo "$result" | sed -n '/^================= RESULT VPC #1 =================$/,/^====================================================$/p')"

  AWS_REGION="$(echo "$summary" | awk -F':' '/Region[[:space:]]*:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tail -n1)"
  VPC_ID="$(echo "$summary" | awk -F':' '/VPC ID[[:space:]]*:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tail -n1)"
  SUBNET_ID="$(echo "$summary" | awk -F':' '/Public Subnet ID[[:space:]]*:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tail -n1)"

  [[ -n "$AWS_REGION" ]] || fail "Failed to parse Region from build_multi_vpc.sh output"
  [[ -n "$VPC_ID" ]] || fail "Failed to parse VPC ID from build_multi_vpc.sh output"
  [[ -n "$SUBNET_ID" ]] || fail "Failed to parse Public Subnet ID from build_multi_vpc.sh output"

  info "Created VPC in region: $AWS_REGION"
  info "Created VPC: $VPC_ID"
  info "Using public subnet: $SUBNET_ID"
}

create_subnet_via_external_script() {
  [[ -n "$VPC_ID" ]] || fail "Cannot create subnet without VPC_ID"
  info "Delegating Subnet creation to external script..."
  # Example:
  # result="$("$SCRIPT_DIR/create_subnet.sh" --region "$AWS_REGION" --vpc-id "$VPC_ID" --json)"
  # SUBNET_ID="$(echo "$result" | jq -r '.subnet_id')"

  fail "Hook not implemented: create_subnet_via_external_script"
}

create_sg_via_external_script() {
  [[ -n "$VPC_ID" ]] || fail "Cannot create security group without VPC_ID"
  info "Delegating Security Group creation to external script..."
  # Example:
  # result="$("$SCRIPT_DIR/create_security_group.sh" --region "$AWS_REGION" --vpc-id "$VPC_ID" --json)"
  # SG_ID="$(echo "$result" | jq -r '.security_group_id')"

  fail "Hook not implemented: create_sg_via_external_script"
}

create_key_via_external_script() {
  local result

  info "Delegating Key Pair creation to manage_aws_security.sh in region $AWS_REGION..."

  result="$("$SCRIPT_DIR/manage_aws_security.sh" --region "$AWS_REGION" --create-key --json)"

  KEY_NAME="$(echo "$result" | jq -r '.key_name')"

  [[ -n "$KEY_NAME" && "$KEY_NAME" != "null" ]] \
    || fail "Failed to parse key_name from manage_aws_security.sh output"

  info "Created Key Pair: $KEY_NAME"
}

####################################
# Choose AWS region interactively if not set via env or CLI
####################################

choose_region_interactively() {
  [[ "$NON_INTERACTIVE" == false ]] || return 0
  [[ -n "${AWS_REGION:-}" ]] || true

  local regions_json count choice current_label
  regions_json="$(
    aws ec2 describe-regions \
      --all-regions \
      --query 'Regions[].RegionName' \
      --output json | jq 'sort'
  )"

  count="$(echo "$regions_json" | jq 'length')"
  (( count > 0 )) || fail "No AWS regions returned."

  echo
  echo "==== Select AWS Region ===="
  for ((i=0; i<count; i++)); do
    local region_name marker
    region_name="$(echo "$regions_json" | jq -r ".[$i]")"
    marker=""
    if [[ -n "${AWS_REGION:-}" && "$region_name" == "$AWS_REGION" ]]; then
      marker=" (default)"
    fi
    printf "%2d) %s%s\n" "$((i+1))" "$region_name" "$marker"
  done

  while true; do
    if [[ -n "${AWS_REGION:-}" ]]; then
      read -r -p "Choose region 1-$count by number or name [current region: $AWS_REGION, Enter=keep]: " choice
      choice="$(echo "$choice" | xargs)"
      if [[ -z "$choice" ]]; then
        info "Using region: $AWS_REGION"
        return 0
      fi
    else
      read -r -p "Choose region by number or name: " choice
      choice="$(echo "$choice" | xargs)"
    fi

    # Update region based on number selection
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      if (( choice >= 1 && choice <= count )); then
        AWS_REGION="$(echo "$regions_json" | jq -r ".[$((choice-1))]")"
        info "Selected region: $AWS_REGION"
        return 0
      fi
      echo "Invalid number. Please choose between 1 and $count."
      continue
    fi

    # As a fallback, allow user to type region name directly
    if echo "$regions_json" | jq -e --arg region "$choice" '.[] | select(. == $region)' >/dev/null; then
        AWS_REGION="$choice"
        info "Selected region: $AWS_REGION"
        return 0
    fi

    echo "Invalid selection. Please enter a valid region name or number from the list."
  done
}


###############################
# Resolve resource flow
################################

resolve_vpc() {
  if [[ -n "$VPC_ID" ]]; then
    if [[ "$CREATE_VPC" == true ]]; then
      warn "--create-vpc ignored because --vpc-id was provided"
    fi
    validate_vpc_exists
    info "Using existing VPC: $VPC_ID"
    return 0
  fi

  if [[ "$CREATE_VPC" == true || "$CREATE_ALL_MISSING" == true ]]; then
    create_vpc_via_external_script
    [[ -n "$VPC_ID" ]] || fail "VPC creation hook returned empty VPC_ID"
    validate_vpc_exists
    info "Created VPC: $VPC_ID"
    return 0
  fi

  choose_vpc_interactively
  validate_vpc_exists
  info "Selected VPC: $VPC_ID"
}

resolve_subnet() {
  if [[ -n "$SUBNET_ID" ]]; then
    if [[ "$CREATE_SUBNET" == true ]]; then
      warn "--create-subnet ignored because --subnet-id was provided"
    fi
    validate_subnet_exists
    validate_subnet_in_vpc
    info "Using existing Subnet: $SUBNET_ID"
    return 0
  fi

  if [[ "$CREATE_SUBNET" == true || "$CREATE_ALL_MISSING" == true ]]; then
    create_subnet_via_external_script
    [[ -n "$SUBNET_ID" ]] || fail "Subnet creation hook returned empty SUBNET_ID"
    validate_subnet_exists
    validate_subnet_in_vpc
    info "Created Subnet: $SUBNET_ID"
    return 0
  fi

  choose_subnet_interactively
  validate_subnet_exists
  validate_subnet_in_vpc
  info "Selected Subnet: $SUBNET_ID"
}

resolve_sg() {
  if [[ -n "$SG_ID" ]]; then
    if [[ "$CREATE_SG" == true ]]; then
      warn "--create-sg ignored because --sg-id was provided"
    fi
    validate_sg_exists
    validate_sg_in_vpc
    info "Using existing Security Group: $SG_ID"
    return 0
  fi

  if [[ "$CREATE_SG" == true || "$CREATE_ALL_MISSING" == true ]]; then
    create_sg_via_external_script
    [[ -n "$SG_ID" ]] || fail "SG creation hook returned empty SG_ID"
    validate_sg_exists
    validate_sg_in_vpc
    info "Created Security Group: $SG_ID"
    return 0
  fi

  choose_sg_interactively
  validate_sg_exists
  validate_sg_in_vpc
  info "Selected Security Group: $SG_ID"
}

resolve_key() {
  if [[ -n "$KEY_NAME" ]]; then
    if [[ "$CREATE_KEY" == true ]]; then
      warn "--create-key ignored because --key-name was provided"
    fi
    validate_key_exists
    info "Using existing Key Pair: $KEY_NAME"
    return 0
  fi

  if [[ "$CREATE_KEY" == true || "$CREATE_ALL_MISSING" == true ]]; then
    create_key_via_external_script
    [[ -n "$KEY_NAME" ]] || fail "Key creation hook returned empty KEY_NAME"
    validate_key_exists
    info "Created Key Pair: $KEY_NAME"
    return 0
  fi

  choose_key_interactively
  validate_key_exists
  info "Selected Key Pair: $KEY_NAME"
}

resolve_os() {
  if [[ -z "$OS_NAME" ]]; then
    choose_os_interactively
  fi
  OS_NAME="$(printf '%s' "$OS_NAME" | tr '[:upper:]' '[:lower:]')"
  validate_os_name
  info "Selected OS: $OS_NAME"
}

resolve_instance_type() {
  if [[ -z "$INSTANCE_TYPE" ]]; then
    choose_instance_type_interactively
  fi

  if [[ "$DRY_RUN" == false ]]; then
    aws ec2 describe-instance-types \
      --region "$AWS_REGION" \
      --instance-types "$INSTANCE_TYPE" \
      --output json >/dev/null \
      || fail "Instance type not available in region $AWS_REGION: $INSTANCE_TYPE"
  fi

  info "Selected instance type: $INSTANCE_TYPE"
}

resolve_storage() {
  choose_storage_interactively
  info "Root disk size: ${ROOT_DISK_SIZE} GiB"
  if [[ "$ADD_EXTRA_DISK" == true ]]; then
    info "Extra disk size: ${DATA_DISK_SIZE} GiB"
  else
    info "Extra disk: none"
  fi
}

resolve_user_data() {
  choose_user_data_interactively
  if [[ -n "$USER_DATA_FILE" ]]; then
    validate_user_data_file
    info "Using user-data file: $USER_DATA_FILE"
  else
    info "No user-data"
  fi
}

resolve_name() {
  choose_name_interactively
  info "Instance Name tag: $INSTANCE_NAME"
}

################################
# AMI selection
################################
resolve_ami() {
  case "$OS_NAME" in
    amazonlinux)
      AMI_ID="$(
        aws ssm get-parameter \
          --region "$AWS_REGION" \
          --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
          --query 'Parameter.Value' \
          --output text
      )"
      ;;
    ubuntu)
      AMI_ID="$(
        aws ec2 describe-images \
          --region "$AWS_REGION" \
          --owners 099720109477 \
          --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" \
          --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
          --output text
      )"
      ;;
    rhel)
      AMI_ID="$(
        aws ec2 describe-images \
          --region "$AWS_REGION" \
          --owners 309956199498 \
          --filters \
            "Name=name,Values=RHEL-9*_HVM-*-x86_64-*" \
            "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" \
          --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
          --output text
      )"
      ;;
    fedora)
      AMI_ID="$(
        aws ec2 describe-images \
          --region "$AWS_REGION" \
          --owners aws-marketplace amazon self \
          --filters \
            "Name=name,Values=Fedora-Cloud-Base-*" \
            "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" \
          --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
          --output text 2>/dev/null || true
      )"
      ;;
    windows)
      AMI_ID="$(
        aws ssm get-parameter \
          --region "$AWS_REGION" \
          --name "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base" \
          --query 'Parameter.Value' \
          --output text
      )"
      ;;
    *)
      fail "Unsupported OS: $OS_NAME"
      ;;
  esac

  [[ -n "$AMI_ID" && "$AMI_ID" != "None" ]] || fail "Could not resolve AMI for OS: $OS_NAME"
  info "Resolved AMI: $AMI_ID"
}

################################
# Block device mappings
################################
build_block_device_mappings() {
  local root_device_name bdm_file
  bdm_file="$TMP_DIR/block-device-mappings.json"

  root_device_name="$(
    aws ec2 describe-images \
      --region "$AWS_REGION" \
      --image-ids "$AMI_ID" \
      --query 'Images[0].RootDeviceName' \
      --output text
  )"

  [[ -n "$root_device_name" && "$root_device_name" != "None" ]] || fail "Could not determine root device name for AMI $AMI_ID"

  if [[ "$ADD_EXTRA_DISK" == true ]]; then
    cat > "$bdm_file" <<EOF
[
  {
    "DeviceName": "$root_device_name",
    "Ebs": {
      "VolumeSize": $ROOT_DISK_SIZE,
      "VolumeType": "gp3",
      "DeleteOnTermination": true
    }
  },
  {
    "DeviceName": "/dev/sdf",
    "Ebs": {
      "VolumeSize": $DATA_DISK_SIZE,
      "VolumeType": "gp3",
      "DeleteOnTermination": false
    }
  }
]
EOF
  else
    cat > "$bdm_file" <<EOF
[
  {
    "DeviceName": "$root_device_name",
    "Ebs": {
      "VolumeSize": $ROOT_DISK_SIZE,
      "VolumeType": "gp3",
      "DeleteOnTermination": true
    }
  }
]
EOF
  fi

  echo "$bdm_file"
}

################################
# Launch
################################
print_summary() {
  echo
  echo "==== Launch Summary ===="
  echo "Region          : $AWS_REGION"
  echo "VPC             : $VPC_ID"
  echo "Subnet          : $SUBNET_ID"
  echo "Security Group  : $SG_ID"
  echo "Key Pair        : $KEY_NAME"
  echo "OS              : $OS_NAME"
  echo "AMI             : $AMI_ID"
  echo "Instance Type   : $INSTANCE_TYPE"
  echo "Root Disk       : ${ROOT_DISK_SIZE} GiB"
  if [[ "$ADD_EXTRA_DISK" == true ]]; then
    echo "Extra Disk      : ${DATA_DISK_SIZE} GiB (kept after termination)"
  else
    echo "Extra Disk      : none"
  fi
  if [[ -n "$USER_DATA_FILE" ]]; then
    echo "User-data       : $USER_DATA_FILE"
  else
    echo "User-data       : none"
  fi
  echo "Name Tag        : $INSTANCE_NAME"
  echo "Non-Interactive : $NON_INTERACTIVE"
  echo "Dry-Run         : $DRY_RUN"
}

launch_instance() {
  local bdm_file
  bdm_file="$(build_block_device_mappings)"

  print_summary

  if [[ "$NON_INTERACTIVE" == false && "$DRY_RUN" == false ]]; then
    local confirm
    read -r -p "Launch instance now? (y/n): " confirm
    confirm="$(printf '%s' "$confirm" | tr '[:upper:]' '[:lower:]')"
    [[ "$confirm" == "y" ]] || fail "Launch cancelled."
  fi

  local cmd=(
    aws ec2 run-instances
    --region "$AWS_REGION"
    --image-id "$AMI_ID"
    --instance-type "$INSTANCE_TYPE"
    --subnet-id "$SUBNET_ID"
    --security-group-ids "$SG_ID"
    --key-name "$KEY_NAME"
    --block-device-mappings "file://$bdm_file"
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"
    --count 1
    --output json
  )

  if [[ -n "$USER_DATA_FILE" ]]; then
    cmd+=( --user-data "file://$USER_DATA_FILE" )
  fi

  if [[ "$DRY_RUN" == true ]]; then
    run_cmd "${cmd[@]}"
    return 0
  fi

  local result instance_id state private_ip public_ip
  result="$("${cmd[@]}")"

  instance_id="$(echo "$result" | jq -r '.Instances[0].InstanceId')"
  state="$(echo "$result" | jq -r '.Instances[0].State.Name')"
  private_ip="$(echo "$result" | jq -r '.Instances[0].PrivateIpAddress // empty')"
  public_ip="$(echo "$result" | jq -r '.Instances[0].PublicIpAddress // empty')"

  echo
  echo "Instance launched successfully."
  echo "Instance ID : $instance_id"
  echo "State       : $state"
  echo "Private IP  : ${private_ip:-N/A}"
  echo "Public IP   : ${public_ip:-N/A}"
}

################################
# Main
################################
main() {
  parse_args "$@"
  check_prereqs
  choose_region_interactively

  resolve_vpc
  resolve_subnet
  resolve_sg
  resolve_key

  resolve_os
  resolve_instance_type
  resolve_storage
  resolve_user_data
  resolve_name

  resolve_ami
  launch_instance
}

main "$@"
