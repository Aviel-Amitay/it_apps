#!/usr/bin/env python3

"""
Example collector outputs for email_notifier.py.

Each case writes JSON in the summary format expected by email_notifier.py:

  python3 collector_script.py --case aws --dummy
  python3 email_notifier.py --config config.yaml --env ../.env --summary ../report/aws_report.json --debug
"""

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional


ROOT_DIR = Path(__file__).resolve().parent.parent
REPORT_DIR = ROOT_DIR / "report"


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def aws_case(args: argparse.Namespace) -> Dict[str, Any]:
    return {
        "source": "aws",
        "action": "ec2_create",
        "subject": "AWS EC2 instance creation summary",
        "send_mode": "one_email",
        "recipients": ["devops@example.com"],
        "body_type": "plain",
        "generated_at": now_iso(),
        "environment": "dev",
        "dummy": args.dummy,
        "body": "\n".join(
            [
                "##########################################",

                "Test email - This email is a test.",
                "##########################################",
                
                "AWS EC2 instance created successfully.",
                "",
                "Region: eu-west-1",
                "VPC ID: vpc-0123456789abcdef0",
                "Subnet ID: subnet-0123456789abcdef0",
                "Security Group: sg-0123456789abcdef0",
                "Key Pair: aws-2026-07-06-eu-west-1-devops",
                "Instance ID: i-0123456789abcdef0",
                "Instance Type: t3.micro",
                "Private IP: 10.10.1.25",
                "Status: running",
            ]
        ),
        "records": [
            {
                "resource": "ec2_instance",
                "name": "dev-tools-01",
                "id": "i-0123456789abcdef0",
                "region": "eu-west-1",
                "status": "running",
            },
            {
                "resource": "security_group",
                "name": "dev-tools-sg",
                "id": "sg-0123456789abcdef0",
                "status": "attached",
            },
        ],
    }


def chef_case(args: argparse.Namespace) -> Dict[str, Any]:
    return {
        "source": "chef",
        "action": "chef_client_run",
        "subject": "Chef client run summary",
        "send_mode": "one_email",
        "recipients": ["devops@example.com"],
        "body_type": "plain",
        "generated_at": now_iso(),
        "environment": "prod",
        "dummy": args.dummy,
        "body": "\n".join(
            [
                "Chef client completed on selected nodes.",
                "",
                "Successful nodes: 2",
                "Warning nodes: 1",
                "Failed nodes: 1",
                "",
                "Failures require review before the next run.",
            ]
        ),
        "records": [
            {
                "node": "web01",
                "run_list": "recipe[base],recipe[sshd]",
                "status": "success",
                "updated_resources": 4,
            },
            {
                "node": "app01",
                "run_list": "recipe[base],recipe[autofs::main-autofs]",
                "status": "warning",
                "message": "Autofs map changed, service restart pending",
            },
            {
                "node": "db01",
                "run_list": "recipe[base]",
                "status": "failed",
                "message": "SSH connection timed out",
            },
        ],
    }


def project_user_record(
    username: str,
    project: str,
    status: str,
    first_name: Optional[str] = None,
    last_name: Optional[str] = None,
    email: Optional[str] = None,
    email_field_name: str = "email",
    manager: Optional[str] = None,
    message: Optional[str] = None,
) -> Dict[str, Any]:
    record = {
        "username": username,
        "project": project,
        "status": status,
        "project_path": f"/projects/{project}/work/{username}",
        "message": message or f"Project workspace status for {username} in {project}: {status}.",
    }

    optional_fields = {
        "first_name": first_name,
        "last_name": last_name,
        "manager": manager,
    }
    record.update({key: value for key, value in optional_fields.items() if value})

    if email:
        record[email_field_name] = email

    return record


def create_project_users_case(args: argparse.Namespace) -> Dict[str, Any]:
    if args.dummy:
        users = [
            project_user_record(
                username="aviela",
                first_name="Aviel",
                last_name="Amitay",
                email="aviela@example.com",
                project="example-project",
                manager="market1",
                status="created",
                message="Project workspace was created successfully.",
            ),
            project_user_record(
                username="danal",
                first_name="Dana",
                last_name="Levi",
                email="danal@example.com",
                project="example-project",
                manager="market1",
                status="already_exists",
                message="Workspace already existed; no directory changes were needed.",
            ),
            project_user_record(
                username="noamc",
                first_name="Noam",
                last_name="Cohen",
                email="noamc@example.com",
                project="another-project",
                manager="infra",
                status="failed",
                message="Project workspace could not be created and requires review.",
            ),
        ]
    else:
        users = [
            project_user_record(
                username=args.username,
                first_name=args.first_name,
                last_name=args.last_name,
                email=args.email,
                email_field_name=args.email_field_name,
                project=args.project,
                manager=args.manager,
                status=args.status,
                message=args.message,
            )
        ]

    return {
        "source": "linux_env",
        "action": "create_project_users",
        "subject": "Project workspace access update",
        "send_mode": "per_user",
        "body_type": "plain",
        "generated_at": now_iso(),
        "environment": "prod",
        "dummy": args.dummy,
        "users": users,
    }


def license_status_case(args: argparse.Namespace) -> Dict[str, Any]:
    return {
        "source": "license_check",
        "action": "license_status",
        "subject": "License server status summary",
        "send_mode": "one_email",
        "recipients": ["devops@example.com", "it@example.com"],
        "body_type": "plain",
        "generated_at": now_iso(),
        "environment": "prod",
        "dummy": args.dummy,
        "body": "\n".join(
            [
                "License status check completed.",
                "",
                "OK: 2",
                "Warning: 1",
                "Critical: 1",
                "",
                "Critical license pool requires immediate cleanup or renewal.",
            ]
        ),
        "records": [
            {
                "server": "license01",
                "feature": "matlab",
                "total": 50,
                "used": 31,
                "available": 19,
                "status": "ok",
            },
            {
                "server": "license01",
                "feature": "synopsys",
                "total": 20,
                "used": 18,
                "available": 2,
                "status": "warning",
            },
            {
                "server": "license02",
                "feature": "cadence",
                "total": 30,
                "used": 30,
                "available": 0,
                "status": "critical",
            },
            {
                "server": "license02",
                "feature": "mentor",
                "total": 15,
                "used": 6,
                "available": 9,
                "status": "ok",
            },
        ],
    }


CASES: Dict[str, Callable[[argparse.Namespace], Dict[str, Any]]] = {
    "aws": aws_case,
    "chef": chef_case,
    "project-users": create_project_users_case,
    "licenses": license_status_case,
}


DEFAULT_FILENAMES = {
    "aws": "aws_report.json",
    "chef": "chef_report.json",
    "project-users": "project_users_report.json",
    "licenses": "license_status_report.json",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate summary JSON files for email_notifier.py."
    )
    parser.add_argument(
        "--case",
        choices=["all", *CASES.keys()],
        default="all",
        help="Example case to generate. Default: all",
    )
    parser.add_argument(
        "--output-dir",
        default=str(REPORT_DIR),
        help=f"Directory where report files are written. Default: {REPORT_DIR}",
    )
    parser.add_argument(
        "--output",
        help="Output file for a single --case. Not valid with --case all.",
    )
    parser.add_argument(
        "--dummy",
        action="store_true",
        help="Generate dummy/sample data for the selected --case, or every case with --case all.",
    )
    parser.add_argument(
        "--project",
        default="project-name",
        help="Project name for --case project-users.",
    )
    parser.add_argument(
        "--username",
        default="username",
        help="Username for --case project-users.",
    )
    parser.add_argument(
        "--first-name",
        help="First name for --case project-users.",
    )
    parser.add_argument(
        "--last-name",
        help="Last name for --case project-users.",
    )
    parser.add_argument(
        "--email",
        help="Email address for --case project-users when using direct email fields.",
    )
    parser.add_argument(
        "--email-field-name",
        default="email",
        help="JSON field name used for the email address. Default: email",
    )
    parser.add_argument(
        "--manager",
        help="Manager or user to copy from for --case project-users.",
    )
    parser.add_argument(
        "--status",
        default="created",
        help="Status for --case project-users. Default: created",
    )
    parser.add_argument(
        "--message",
        help="Custom message for --case project-users.",
    )
    return parser.parse_args()


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")


def selected_cases(case_name: str) -> List[str]:
    if case_name == "all":
        return list(CASES.keys())
    return [case_name]


def main() -> int:
    args = parse_args()

    if args.case == "all" and args.output:
        raise SystemExit("--output can only be used with a single --case")

    output_dir = Path(args.output_dir)
    written_files = []

    for case_name in selected_cases(args.case):
        output_path = (
            Path(args.output)
            if args.output
            else output_dir / DEFAULT_FILENAMES[case_name]
        )
        write_json(output_path, CASES[case_name](args))
        written_files.append(output_path)

    for path in written_files:
        print(f"Created {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
