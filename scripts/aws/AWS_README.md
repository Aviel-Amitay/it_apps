# AWS Scripts

This folder contains the AWS-focused automation scripts used by the project.  
The main repository README already gives the high-level overview, so this file focuses on what each script actually does when you run it.

## `build_multi_vpc.sh`

This script is an interactive VPC builder for creating one or two VPC environments.

During the workflow it:
- Lets you choose whether to build 1 or 2 VPCs
- Lets you work in one region or split VPCs across different regions
- Prompts for VPC name tags and CIDR blocks
- Prompts for public and private subnet names, CIDRs, and availability zones
- Lets you enable auto-assign public IPs on the public subnet
- Creates and attaches an internet gateway
- Creates route tables and associates them with the correct subnets
- Optionally creates a NAT gateway and a private default route through it
- Prints a final result summary for the created VPCs

Operational notes:
- The script is strongly interactive and is designed for guided creation rather than silent automation first.
- `--dry-run` shows the intended plan without creating resources.
- `--json` is available for flows that want machine-readable output.
- NAT gateways cost money, so the private-subnet outbound design has a billing impact.

## `manage_aws_security.sh`

This script is the security and SSH-key utility for the AWS folder. It has two main responsibilities: security groups and EC2 key pairs.

### Security group workflow

In the security group menu, the script can:
- List VPCs in the selected region
- Let you choose a VPC before working on its security groups
- List security groups inside that VPC
- Show security group details including ingress and egress rules
- Create a new security group with a name and description
- Apply predefined ingress profiles such as:
  - SSH on port 22
  - Common web/app ports such as 80, 443, 8080, 8443, 3000, and 123
  - Office CIDR-based rules
- Add custom single-port or port-range ingress rules
- Modify existing security groups by adding more rules
- Attach a security group to an EC2 instance by updating the primary ENI
- Delete a security group after confirmation

### Key pair workflow

In the key-pair menu, the script can:
- List existing AWS key pairs
- Create a new key pair
- Save the private key under `~/.ssh`
- Support `pem` or `ppk`-oriented flows
- Delete an AWS key pair
- Remove the related local PEM file if it finds one

### Delegated mode

This script is also used by other scripts in this folder as a helper:
- `--create-key --json` runs directly into key creation and returns JSON
- `--create-sg --vpc-id <id> --json` runs directly into security-group creation for a chosen VPC and returns JSON

That delegated mode is what allows `manage_ec2_instance.sh` to call it as part of a larger provisioning flow.

## `manage_ec2_instance.sh`

This script is the EC2 launcher and orchestration layer for the folder.

Its role is not just "create an instance". It walks through the full dependency chain needed before launch and decides whether to reuse existing AWS resources, ask the user to select them, or delegate creation to the other scripts.

### Resource resolution flow

For each required resource, the script follows a similar pattern:
- If a value was provided by CLI flag, it validates that resource and uses it
- If creation flags were requested, it delegates creation where supported
- If nothing was provided, it falls back to interactive selection

This applies to:
- VPC
- Subnet
- Security group
- Key pair

### What it resolves before launch

After infrastructure selection, the script continues with instance-specific decisions:
- OS selection
- AMI lookup based on the selected OS
- Instance type selection and validation
- Root disk sizing
- Optional extra EBS disk sizing
- Optional user-data file selection or inline paste flow
- Instance name tag

### Launch behavior

When launching, the script:
- Builds block-device mappings dynamically from the AMI root device
- Uses the chosen subnet, security group, and key pair
- Applies `Name` and `Destroy=nuke` tags
- Runs `aws ec2 run-instances`
- Prints the launched instance ID, state, and IP information

### Delegation behavior

This script can call:
- `build_multi_vpc.sh` to create a VPC when `--create-vpc` is used
- `manage_aws_security.sh` to create a security group when `--create-sg` is used
- `manage_aws_security.sh` to create a key pair when `--create-key` is used

Important limitation:
- The subnet delegation hook exists, but `--create-subnet` is still not implemented in the current script. Subnets must currently be selected from existing resources unless they came from the VPC creation flow.

### Supported operating systems

The script currently knows how to resolve AMIs for:
- Amazon Linux
- Ubuntu
- RHEL
- Fedora
- Windows Server


### Thank you 