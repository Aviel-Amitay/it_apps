# IT Apps: Automation Scripts for IT Operations

This repository contains a collection of Bash scripts used by the IT department to automate common administrative tasks such as user provisioning, virtual machine management, backups and environment setup.  The scripts are organized into functional directories and are designed to run on internal servers with access to Active Directory (AD), VMware vSphere, Chef, and other infrastructure tools.  Below is an overview of the key scripts and directories.

## Core Scripts

### customize_company_updated.sh

This interactive script helps you customise company‑specific values used across all the other scripts.  It scans existing files to detect the current AD domain, e‑mail domain, DC hostname, and other variables, then prompts the operator for replacements:

- **Detect and update domains:** It uses regular expressions to detect the current company’s internal AD domain (e.g., `in.example.local`) and email domain (e.g., `example.com`).  After confirming the matches, it prompts for new values and builds `sed` replacement patterns to update all scripts accordingly.
- **Update Domain Controller (DC) details:** The script finds references to existing DCs (including admin user names) and allows you to update them to the new company’s host and account names.  It then performs replacements across all files.
- **Backup configuration:** In the same run, you can change backup IPs and update the `SCRIPT_BASE` path used by launcher scripts.  The script supports dry‑run mode and logs changes to a file.  This makes it useful for cloning the repository into a new environment and quickly replacing company‑specific values.

### launcher‑app.sh

`launcher-app.sh` provides a user‑friendly menu interface for running the other scripts.  At startup, it sets environment variables such as `SCRIPT_BASE`, `LINUX_SCRIPT_DIR`, and `CHEF_SCRIPT_DIR` then asks for the IT username to log actions.  The script defines categories (User Actions, Environment Actions, Machine Actions, and Backup Actions) containing arrays of script names and descriptions.  When executed, it displays the menu, lets the user select a script, and runs it in the appropriate directory (top‑level scripts, `linux_env` or `chef`) while logging each action.  Use this wizard to simplify navigation and ensure consistent logging when running scripts.

## Top‑level `scripts` directory

The `scripts` directory contains standalone automation scripts (excluding `linux_env` and `chef`, which are covered separately).  Here is a brief description of the main scripts:

| Script | Summary |
| --- | --- |
| **Jenkins_status.sh** | Queries a Jenkins job’s last build status using `curl` and `jq`.  It prints whether the job succeeded, is running, or failed, and outputs a link to the job’s page. |
| **add_user_to_ad.sh** | Adds a new user to Active Directory.  It collects user details, constructs a username and password, and uses `dsadd` over SSH to create the account.  It also sends an email with credentials to the new user. |
| **automate_external_backup.sh** | Automates offsite backups to external disks.  It detects available backup disks via `ping`, prompts for the user, retention days, and deletion of old data, and runs an `rsync` backup over SSH to the backup server. |
| **bootstrap_machine.sh** | Bootstraps a new host with Chef.  Prompts for a hostname and role, then runs `knife bootstrap` from a build server, optionally applying specific tags.  Suitable for quickly bringing a machine under configuration management. |
| **check_licenses_servers.sh** | Checks usage on licence servers by querying ports with `/tools/lmtools/bin/lmstat` for different vendors, printing results for each license pool. |
| **compare_rpms.sh** | Compares installed packages on two hosts.  It detects the OS (RPM or DEB), fetches the package lists with `rpm -qa` or `dpkg-query`, aligns them with `join` and outputs differences. |
| **delete_vm.sh** | Deletes a virtual machine and cleans up related records.  It removes the AD computer object and DNS record with `dsrm`/`dnscmd` and uses `knife vsphere vm delete` to remove the VM from vCenter. |
| **export_active_users.sh** | Exports details of active AD users.  It runs `ldapsearch`, extracts attributes such as name, employee ID, email and manager, and writes them to a CSV file. |
| **new_vm.sh** | Creates a new virtual machine from templates.  It asks for a hostname and type, then calls `knife vsphere vm clone` with appropriate run‑lists, tags, datastores and network settings for categories like VLSI, contractors or Ubuntu. |
| **setup_linux_env.sh** | Sets up a user’s Linux development environment.  Accepts command‑line flags for username, project, copy user, etc., and prompts for missing values.  It creates home directories with correct group membership and permissions; handles special projects requiring additional volumes or VNC setups; monitors Jenkins build status using `Jenkins_status.sh`; and finally runs Chef to apply configuration. |
| **sge_actions.sh** | Provides a simple menu for common Sun Grid Engine (SGE) tasks such as listing jobs, adding submit hosts, editing queues and showing total slot usage. |
| **speed_test.sh** | Downloads and runs a Python‑based speed test script to measure network throughput. |

These scripts can be executed individually or via the `launcher-app.sh` wizard.  They automate repetitive tasks and enforce consistent procedures across the IT team.

## `scripts/linux_env` directory

Scripts in `linux_env` focus on user and project environment setup on Linux hosts.  They help manage home directories, project storage and automount configurations:

- **create_project_work_dir.sh**: prompts for user, project and manager storage path, then constructs the network path and creates project work directories with the appropriate group and permissions.  It handles differences between employees and contractors.
- **update_autofs_maps.sh**: updates AutoFS map files.  It parses arguments, determines the project template from Chef cookbooks, locates entries for the copy user, builds new map entries for the specified user and project, commits changes via Git and runs Chef to deploy them.  Use this script when adding new projects or updating automount configurations.

## `scripts/chef` directory

The `chef` directory contains tools for managing the Chef configuration management environment:

- **edit_cookbook_metadata.sh**: bumps the patch version in a cookbook’s `metadata.rb` file.  It lets you select a cookbook, confirms the change and runs an SSH command to edit the file.
- **upload_cookbook.sh**: updates the Chef repository on the build server and uploads selected or all cookbooks using `knife cookbook upload`.
- **edit_chef_node.sh**: opens a Chef node for editing with `knife node edit` on the Chef server.
- **run_full_chef_client.sh**: runs `chef-client` across nodes matching a specified role.  It prompts for the role, builds a `knife ssh` command, logs output and executes it, allowing bulk configuration updates.

Other scripts in this directory support environment‑specific tasks such as running `chef-client` only on AutoFS nodes.  These tools streamline Chef operations and keep configuration in sync.

## Contribution & Usage

These scripts are designed for use by an internal IT team on trusted networks.  Before running them:

1. Clone the repository to a server that has SSH access to domain controllers, backup servers and VMware vCenter.
2. Run `customize_company_updated.sh` to update all company‑specific variables (AD domain, email domain, DC hostnames, etc.) so the scripts align with your infrastructure.
3. Use `launcher-app.sh` to choose and run the desired script from an interactive menu.
4. Review each script’s usage instructions and ensure you have the necessary permissions (e.g., Chef admin, vSphere admin, backup server access).

Automation can save time, but also has wide‑ranging effects—ensure you understand each script before running it in production.  Feel free to fork the repository and contribute improvements or bug fixes via pull requests.

## Show Your Support

If you find these scripts helpful, please consider giving this repository a ⭐ star or leaving a brief review on GitHub.  Your support helps this project shine and encourages further development.  Thank you!
