#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Globals / defaults
###############################################################################
SCRIPT_NAME="$(basename "$0")"

AWS_PROFILE="${AWS_PROFILE:-default}"
DRY_RUN="no"
AUTO_APPROVE="no"

DEFAULT_VPC_COUNT="1"
DEFAULT_REGION_1="us-east-1"
DEFAULT_REGION_2="eu-central-1"
DEFAULT_ENABLE_NAT="yes"
DEFAULT_PUBLIC_AUTO_IP="yes"

###############################################################################
# Build result VPCs
###############################################################################
BUILT_VPC_IDS=()
BUILT_VPC_NAMES=()
BUILT_VPC_REGIONS=()
BUILT_PUBLIC_SUBNET_IDS=()
BUILT_PRIVATE_RT_IDS=()


###############################################################################
# Usage / help
###############################################################################
usage() {
  cat <<'EOF'
Usage:
  build_multi_vpc.sh [options]

Description:
  Interactive AWS VPC builder that creates 1 or 2 VPCs.
  Each VPC can be in a different AWS region.
  For each VPC, the script creates:
    - VPC
    - 1 public subnet
    - 1 private subnet
    - Internet Gateway
    - public route table + default route
    - optional NAT Gateway
    - private route table + optional NAT route

Options:
  -p, --profile NAME     AWS CLI profile to use (default: current env/default)
  -n, --dry-run          Prompt only, print plan, do not create resources
  -y, --yes              Auto-approve final confirmation
  -h, --help             Show this help

Examples:
  ./build_multi_vpc.sh
  ./build_multi_vpc.sh --profile mylab
  ./build_multi_vpc.sh --profile mylab --dry-run
  ./build_multi_vpc.sh -p mylab -y

Notes:
  - VPC is regional, not zonal.
  - Subnets are created in specific Availability Zones.
  - NAT Gateway is optional and costs money.
EOF
}

###############################################################################
# Logging helpers
###############################################################################
log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

###############################################################################
# macOS-compatible prompt helpers
###############################################################################
prompt_with_default() {
  local __var_name="$1"
  local __prompt="$2"
  local __default="$3"
  local __input

  read -r -p "$__prompt [$__default]: " __input
  __input="${__input:-$__default}"
  printf -v "$__var_name" '%s' "$__input"
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
        echo "Please enter yes or no."
        ;;
    esac
  done
}

prompt_action() {
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
      e|edit|return|back)
        printf -v "$__var_name" '%s' "edit"
        return 0
        ;;
      n|no|cancel|quit|exit)
        printf -v "$__var_name" '%s' "cancel"
        return 0
        ;;
      *)
        echo "Please enter: yes, edit, or cancel."
        ;;
    esac
  done
}

###############################################################################
# Validation / dependencies
###############################################################################
require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_int_1_or_2() {
  case "$1" in
    1|2) return 0 ;;
    *) return 1 ;;
  esac
}

aws_cli() {
  aws --profile "$AWS_PROFILE" "$@"
}

###############################################################################
# Region / AZ helpers
###############################################################################
get_regions() {
  aws_cli ec2 describe-regions --query 'Regions[].RegionName' --output text
}

print_regions() {
  log "Available AWS regions:"
  get_regions | tr '\t' '\n' | sed 's/^/  - /'
}

get_available_azs() {
  local region="$1"

  aws_cli ec2 describe-availability-zones \
    --region "$region" \
    --query 'AvailabilityZones[?State==`available`].ZoneName' \
    --output text | tr '\t' '\n'
}

print_azs() {
  local region="$1"
  local az
  log "Available AZs in region $region:"
  while IFS= read -r az; do
    [[ -n "$az" ]] && printf '  - %s\n' "$az"
  done < <(get_available_azs "$region")
}

###############################################################################
# Interactive collection
###############################################################################
collect_vpc_inputs() {
  local idx="$1"
  local default_region="$DEFAULT_REGION_1"
  local first_az=""

  [[ "$idx" -eq 2 ]] && default_region="$DEFAULT_REGION_2"

  echo "########## Configuration for VPC #$idx ###################"
  echo "Available AWS regions:"
  print_regions
  echo
  prompt_with_default "VPC_REGION_$idx" "VPC #$idx region" "$default_region"
  prompt_with_default "VPC_NAME_$idx"   "VPC #$idx name tag" "vpc-$idx"
  prompt_with_default "VPC_CIDR_$idx"   "VPC #$idx IPv4 CIDR" "10.$idx.0.0/16"

  first_az="$(get_available_azs "$(eval echo "\$VPC_REGION_$idx")" | head -n 1)"

  echo
  echo "##########Attention - Configuration for the PUBLIC subnet ###################"
  echo "Available AZs for PUBLIC subnet in region $(eval echo "\$VPC_REGION_$idx"):"
  print_azs "$(eval echo "\$VPC_REGION_$idx")"
  echo

  prompt_with_default "PUBLIC_AZ_$idx"          "VPC #$idx public subnet AZ" "$first_az"
  prompt_with_default "PUBLIC_SUBNET_NAME_$idx" "VPC #$idx public subnet name" "public-subnet-vpc-$idx"
  prompt_with_default "PUBLIC_SUBNET_CIDR_$idx" "VPC #$idx public subnet IPv4 CIDR" "10.$idx.1.0/24"
  prompt_yes_no "PUBLIC_AUTO_IP_$idx" "VPC #$idx enable auto-assign public IPv4 on public subnet?" "$DEFAULT_PUBLIC_AUTO_IP"

  echo
  echo "##########Attention - Configuration for the PRIVATE subnet ###################"
  echo "Available AZs for PRIVATE subnet in region $(eval echo "\$VPC_REGION_$idx"):"
  print_azs "$(eval echo "\$VPC_REGION_$idx")"
  echo

  prompt_with_default "PRIVATE_AZ_$idx"          "VPC #$idx private subnet AZ" "$first_az"
  prompt_with_default "PRIVATE_SUBNET_NAME_$idx" "VPC #$idx private subnet name" "private-subnet-vpc-$idx"
  prompt_with_default "PRIVATE_SUBNET_CIDR_$idx" "VPC #$idx private subnet IPv4 CIDR" "10.$idx.2.0/24"

}

###############################################################################
# Summary printer
###############################################################################
print_vpc_summary() {
  local idx="$1"

  local region name vpc_cidr
  local public_az public_name public_cidr
  local private_az private_name private_cidr
  # local enable_nat public_auto_ip

  region="$(eval echo "\$VPC_REGION_$idx")"
  name="$(eval echo "\$VPC_NAME_$idx")"
  vpc_cidr="$(eval echo "\$VPC_CIDR_$idx")"
  public_az="$(eval echo "\$PUBLIC_AZ_$idx")"
  public_name="$(eval echo "\$PUBLIC_SUBNET_NAME_$idx")"
  public_cidr="$(eval echo "\$PUBLIC_SUBNET_CIDR_$idx")"
  private_az="$(eval echo "\$PRIVATE_AZ_$idx")"
  private_name="$(eval echo "\$PRIVATE_SUBNET_NAME_$idx")"
  private_cidr="$(eval echo "\$PRIVATE_SUBNET_CIDR_$idx")"
  public_auto_ip="$(eval echo "\$PUBLIC_AUTO_IP_$idx")"

  echo "------------------------------------------------------------"
  echo "VPC #$idx"
  echo "  Region                : $region"
  echo "  VPC Name              : $name"
  echo "  VPC CIDR              : $vpc_cidr"
  echo "  Public Subnet Name    : $public_name"
  echo "  Public Subnet CIDR    : $public_cidr"
  echo "  Public Subnet AZ      : $public_az"
  echo "  Public Auto IPv4      : $public_auto_ip"
  echo "  Private Subnet Name   : $private_name"
  echo "  Private Subnet CIDR   : $private_cidr"
  echo "  Private Subnet AZ     : $private_az"
}

###############################################################################
# Creation functions
###############################################################################
create_vpc() {
  local region="$1"
  local vpc_name="$2"
  local vpc_cidr="$3"

  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "dryrun-vpc-${vpc_name}"
    return 0
  fi

  local vpc_id
  vpc_id="$(
    aws_cli ec2 create-vpc \
      --region "$region" \
      --cidr-block "$vpc_cidr" \
      --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$vpc_name}]" \
      --query 'Vpc.VpcId' \
      --output text
  )"

  aws_cli ec2 modify-vpc-attribute \
    --region "$region" \
    --vpc-id "$vpc_id" \
    --enable-dns-support '{"Value":true}' >/dev/null

  aws_cli ec2 modify-vpc-attribute \
    --region "$region" \
    --vpc-id "$vpc_id" \
    --enable-dns-hostnames '{"Value":true}' >/dev/null

  echo "$vpc_id"
}

create_subnet() {
  local region="$1"
  local vpc_id="$2"
  local subnet_name="$3"
  local subnet_cidr="$4"
  local az="$5"

  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "dryrun-subnet-${subnet_name}"
    return 0
  fi

  aws_cli ec2 create-subnet \
    --region "$region" \
    --vpc-id "$vpc_id" \
    --cidr-block "$subnet_cidr" \
    --availability-zone "$az" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$subnet_name}]" \
    --query 'Subnet.SubnetId' \
    --output text
}

enable_public_ip_auto_assign() {
  local region="$1"
  local subnet_id="$2"

  [[ "$DRY_RUN" == "yes" ]] && return 0

  aws_cli ec2 modify-subnet-attribute \
    --region "$region" \
    --subnet-id "$subnet_id" \
    --map-public-ip-on-launch >/dev/null
}

create_internet_gateway() {
  local region="$1"
  local vpc_id="$2"
  local igw_name="$3"

  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "dryrun-igw-${igw_name}"
    return 0
  fi

  local igw_id
  igw_id="$(
    aws_cli ec2 create-internet-gateway \
      --region "$region" \
      --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$igw_name}]" \
      --query 'InternetGateway.InternetGatewayId' \
      --output text
  )"

  aws_cli ec2 attach-internet-gateway \
    --region "$region" \
    --internet-gateway-id "$igw_id" \
    --vpc-id "$vpc_id" >/dev/null

  echo "$igw_id"
}

create_route_table() {
  local region="$1"
  local vpc_id="$2"
  local rt_name="$3"

  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "dryrun-rt-${rt_name}"
    return 0
  fi

  aws_cli ec2 create-route-table \
    --region "$region" \
    --vpc-id "$vpc_id" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$rt_name}]" \
    --query 'RouteTable.RouteTableId' \
    --output text
}

create_igw_route() {
  local region="$1"
  local route_table_id="$2"
  local igw_id="$3"

  [[ "$DRY_RUN" == "yes" ]] && return 0

  aws_cli ec2 create-route \
    --region "$region" \
    --route-table-id "$route_table_id" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$igw_id" >/dev/null
}

create_nat_route() {
  local region="$1"
  local route_table_id="$2"
  local nat_gateway_id="$3"

  [[ "$DRY_RUN" == "yes" ]] && return 0

  aws_cli ec2 create-route \
    --region "$region" \
    --route-table-id "$route_table_id" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$nat_gateway_id" >/dev/null
}

associate_route_table() {
  local region="$1"
  local route_table_id="$2"
  local subnet_id="$3"

  [[ "$DRY_RUN" == "yes" ]] && return 0

  aws_cli ec2 associate-route-table \
    --region "$region" \
    --route-table-id "$route_table_id" \
    --subnet-id "$subnet_id" >/dev/null
}

create_nat_gateway() {
  local region="$1"
  local public_subnet_id="$2"
  local nat_name="$3"

  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "dryrun-nat-${nat_name}"
    return 0
  fi

  local eip_alloc_id nat_id

  eip_alloc_id="$(
    aws_cli ec2 allocate-address \
      --region "$region" \
      --domain vpc \
      --query 'AllocationId' \
      --output text
  )"

  nat_id="$(
    aws_cli ec2 create-nat-gateway \
      --region "$region" \
      --subnet-id "$public_subnet_id" \
      --allocation-id "$eip_alloc_id" \
      --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$nat_name}]" \
      --query 'NatGateway.NatGatewayId' \
      --output text
  )"

  log "Waiting for NAT Gateway $nat_id to become available..."
  aws_cli ec2 wait nat-gateway-available \
    --region "$region" \
    --nat-gateway-ids "$nat_id"

  echo "$nat_id"
}

###############################################################################
# VPC workflow
###############################################################################
build_one_vpc() {
  local idx="$1"

  local region name vpc_cidr
  local public_az public_name public_cidr public_auto_ip
  local private_az private_name private_cidr enable_nat

  region="$(eval echo "\$VPC_REGION_$idx")"
  name="$(eval echo "\$VPC_NAME_$idx")"
  vpc_cidr="$(eval echo "\$VPC_CIDR_$idx")"

  public_az="$(eval echo "\$PUBLIC_AZ_$idx")"
  public_name="$(eval echo "\$PUBLIC_SUBNET_NAME_$idx")"
  public_cidr="$(eval echo "\$PUBLIC_SUBNET_CIDR_$idx")"
  public_auto_ip="$(eval echo "\$PUBLIC_AUTO_IP_$idx")"

  private_az="$(eval echo "\$PRIVATE_AZ_$idx")"
  private_name="$(eval echo "\$PRIVATE_SUBNET_NAME_$idx")"
  private_cidr="$(eval echo "\$PRIVATE_SUBNET_CIDR_$idx")"


  local vpc_id public_subnet_id private_subnet_id igw_id
  local public_rt_id private_rt_id nat_id

  log "Creating VPC #$idx in region $region..."
  vpc_id="$(create_vpc "$region" "$name" "$vpc_cidr")"
  log "Created VPC: $vpc_id"

  log "Creating Internet Gateway..."
  igw_id="$(create_internet_gateway "$region" "$vpc_id" "${name}-igw")"
  log "Created IGW: $igw_id"

  log "Creating public subnet..."
  public_subnet_id="$(create_subnet "$region" "$vpc_id" "$public_name" "$public_cidr" "$public_az")"
  log "Created public subnet: $public_subnet_id"

  if [[ "$public_auto_ip" == "yes" ]]; then
    log "Enabling auto-assign public IPv4 on public subnet..."
    enable_public_ip_auto_assign "$region" "$public_subnet_id"
  fi

  log "Creating private subnet..."
  private_subnet_id="$(create_subnet "$region" "$vpc_id" "$private_name" "$private_cidr" "$private_az")"
  log "Created private subnet: $private_subnet_id"

  log "Creating public route table..."
  public_rt_id="$(create_route_table "$region" "$vpc_id" "${name}-public-rt")"
  log "Created public route table: $public_rt_id"

  log "Creating default route 0.0.0.0/0 to IGW..."
  create_igw_route "$region" "$public_rt_id" "$igw_id"

  log "Associating public route table with public subnet..."
  associate_route_table "$region" "$public_rt_id" "$public_subnet_id"

  log "Creating private route table..."
  private_rt_id="$(create_route_table "$region" "$vpc_id" "${name}-private-rt")"
  log "Created private route table: $private_rt_id"

  if [[ "$enable_nat" == "yes" ]]; then
    log "Creating NAT Gateway in public subnet..."
    nat_id="$(create_nat_gateway "$region" "$public_subnet_id" "${name}-nat")"
    log "Created NAT Gateway: $nat_id"

    log "Creating default route 0.0.0.0/0 in private route table to NAT..."
    create_nat_route "$region" "$private_rt_id" "$nat_id"
  else
    warn "NAT disabled for VPC #$idx. Private subnet will not have outbound internet route."
  fi

  log "Associating private route table with private subnet..."
  associate_route_table "$region" "$private_rt_id" "$private_subnet_id"

  BUILT_VPC_IDS[$idx]="$vpc_id"
  BUILT_VPC_NAMES[$idx]="$name"
  BUILT_VPC_REGIONS[$idx]="$region"
  BUILT_PUBLIC_SUBNET_IDS[$idx]="$public_subnet_id"
  BUILT_PRIVATE_RT_IDS[$idx]="$private_rt_id"

  echo
  echo "================= RESULT VPC #$idx ================="
  echo "Region               : $region"
  echo "VPC ID               : $vpc_id"
  echo "Public Subnet ID     : $public_subnet_id"
  echo "Private Subnet ID    : $private_subnet_id"
  echo "IGW ID               : $igw_id"
  echo "Public Route Table   : $public_rt_id"
  echo "Private Route Table  : $private_rt_id"
  echo "NAT Gateway ID       : ${nat_id:-N/A}"
  echo "===================================================="
  echo
}

###############################################################################
# Argument parsing
###############################################################################

# Build a NAT Gateway route in the private route table if enabled
post_build_nat_workflow() {
  local create_nat_answer
  local selected_idx
  local region
  local name
  local public_subnet_id
  local private_rt_id
  local nat_id

  echo
  prompt_yes_no create_nat_answer "Do you want to create a NAT Gateway now for one of the created VPCs?" "$DEFAULT_ENABLE_NAT"

  if [[ "$create_nat_answer" != "yes" ]]; then
    log "Skipping NAT Gateway creation."
    return 0
  fi

  echo
  echo "Available built VPCs:"
  local i
  for i in 1 2; do
    if [[ -n "${BUILT_VPC_IDS[$i]:-}" ]]; then
      echo "  $i) Name=${BUILT_VPC_NAMES[$i]} Region=${BUILT_VPC_REGIONS[$i]} VpcId=${BUILT_VPC_IDS[$i]}"
    fi
  done
  echo

  while true; do
    read -r -p "Select VPC number for NAT creation: " selected_idx
    case "$selected_idx" in
      1|2)
        if [[ -n "${BUILT_VPC_IDS[$selected_idx]:-}" ]]; then
          break
        else
          echo "VPC #$selected_idx was not built in this run."
        fi
        ;;
      *)
        echo "Please enter 1 or 2."
        ;;
    esac
  done

  region="${BUILT_VPC_REGIONS[$selected_idx]}"
  name="${BUILT_VPC_NAMES[$selected_idx]}"
  public_subnet_id="${BUILT_PUBLIC_SUBNET_IDS[$selected_idx]}"
  private_rt_id="${BUILT_PRIVATE_RT_IDS[$selected_idx]}"

  log "Creating NAT Gateway for VPC #$selected_idx ($name) in region '$region'..."
  nat_id="$(create_nat_gateway "$region" "$public_subnet_id" "${name}-nat")"
  log "Created NAT Gateway: $nat_id"

  log "Creating default route 0.0.0.0/0 in private route table to NAT..."
  create_nat_route "$region" "$private_rt_id" "$nat_id"

  log "Post-build NAT setup completed for VPC #$selected_idx."
}

# End

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--profile)
        [[ $# -lt 2 ]] && die "Missing value for $1"
        AWS_PROFILE="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN="yes"
        shift
        ;;
      -y|--yes)
        AUTO_APPROVE="yes"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1. Use --help."
        ;;
    esac
  done
}

###############################################################################
# Main
###############################################################################
main() {
  parse_args "$@"

  require_command aws

  log "Using AWS profile: $AWS_PROFILE"
  [[ "$DRY_RUN" == "yes" ]] && warn "Dry-run mode enabled. No resources will be created."

  echo
  echo "This builder creates 1 or 2 VPCs."
  echo "Each VPC can be in the same or a different region."
  echo "Each VPC will have:"
  echo "  - 1 public subnet"
  echo "  - 1 private subnet"
  echo "  - Internet Gateway"
  echo "  - public route table"
  echo "  - optional NAT Gateway"
  echo "  - private route table"
  echo

  while true; do
    prompt_with_default VPC_COUNT "How many VPCs do you want to create? (1 or 2)" "$DEFAULT_VPC_COUNT"
    if validate_int_1_or_2 "$VPC_COUNT"; then
      break
    fi
    echo "Please enter only 1 or 2."
  done
while true; do
  echo
  collect_vpc_inputs 1
  if [[ "$VPC_COUNT" == "2" ]]; then
    echo
    collect_vpc_inputs 2
  fi

  echo
  echo "================ CONFIGURATION SUMMARY ================"
  print_vpc_summary 1
  if [[ "$VPC_COUNT" == "2" ]]; then
    print_vpc_summary 2
  fi
  echo "======================================================"
  echo

  if [[ "$AUTO_APPROVE" == "yes" ]]; then
    break
  fi

  prompt_action USER_ACTION "Proceed with this configuration? (yes=apply, edit=change, cancel=exit)" "yes"

  case "$USER_ACTION" in
    yes)
      break
      ;;
    edit)
      echo
      log "Returning to configuration prompts..."
      continue
      ;;
    cancel)
      die "Operation cancelled by user."
      ;;
  esac
done

echo
build_one_vpc 1
if [[ "$VPC_COUNT" == "2" ]]; then
  build_one_vpc 2
fi

  log "All requested VPC builds completed."
  post_build_nat_workflow
}

main "$@"
