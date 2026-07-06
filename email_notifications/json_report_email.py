#!/usr/bin/env python3

"""
Build an HTML report from a JSON file and send it through the configured
notification SMTP connection.
"""

import argparse
import html
import json
import smtplib
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from email_notifier import Config, load_env


COMMON_RECORD_KEYS = ("users", "items", "data", "results", "rows", "records")
APP_DIR = Path(__file__).resolve().parent
ROOT_DIR = APP_DIR.parent
DEFAULT_CONFIG_FILE = APP_DIR / "config.yaml"
DEFAULT_ENV_FILE = ROOT_DIR / ".env"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a readable HTML email report from a JSON file."
    )
    parser.add_argument("-c", "--config", default=str(DEFAULT_CONFIG_FILE), help="Notification config file")
    parser.add_argument("-e", "--env", default=str(DEFAULT_ENV_FILE), help="Environment file with SMTP secrets")
    parser.add_argument("-i", "--input", required=True, help="Source JSON file")
    parser.add_argument("-s", "--subject", default="Automation report", help="Email subject")
    parser.add_argument("-t", "--title", help="Report title shown inside the email")
    parser.add_argument(
        "-r",
        "--recipient",
        action="append",
        dest="recipients",
        help="Recipient email address. Can be used more than once.",
    )
    parser.add_argument(
        "--records-key",
        help="JSON key that contains the list of records. Auto-detected if omitted.",
    )
    parser.add_argument(
        "--output-html",
        help="Write the generated HTML to a file before sending.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Build the report but do not send it")
    return parser.parse_args()


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as stream:
        return json.load(stream)


def extract_records(data: Any, records_key: Optional[str]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    metadata: Dict[str, Any] = {}

    if isinstance(data, list):
        return normalize_records(data), metadata

    if not isinstance(data, dict):
        return [{"value": data}], metadata

    key = records_key or next(
        (candidate for candidate in COMMON_RECORD_KEYS if isinstance(data.get(candidate), list)),
        None,
    )

    if key:
        metadata = {k: v for k, v in data.items() if k != key}
        return normalize_records(data.get(key, [])), metadata

    scalar_metadata = {
        k: v for k, v in data.items() if not isinstance(v, (dict, list))
    }
    if scalar_metadata:
        return [scalar_metadata], {}

    return [flatten_record(data)], {}


def normalize_records(records: Iterable[Any]) -> List[Dict[str, Any]]:
    normalized: List[Dict[str, Any]] = []
    for item in records:
        if isinstance(item, dict):
            normalized.append(flatten_record(item))
        else:
            normalized.append({"value": item})
    return normalized


def flatten_record(record: Dict[str, Any], prefix: str = "") -> Dict[str, Any]:
    flattened: Dict[str, Any] = {}
    for key, value in record.items():
        name = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, dict):
            flattened.update(flatten_record(value, name))
        elif isinstance(value, list):
            flattened[name] = ", ".join(format_value(item) for item in value)
        else:
            flattened[name] = value
    return flattened


def format_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def collect_columns(records: Sequence[Dict[str, Any]]) -> List[str]:
    columns: List[str] = []
    seen = set()
    for record in records:
        for key in record:
            if key not in seen:
                seen.add(key)
                columns.append(key)
    return columns


def render_html_report(
    title: str,
    source_path: str,
    records: Sequence[Dict[str, Any]],
    metadata: Dict[str, Any],
) -> str:
    columns = collect_columns(records)
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    metadata_rows = "".join(
        f"<tr><th>{escape(key)}</th><td>{escape(format_value(value))}</td></tr>"
        for key, value in metadata.items()
        if not isinstance(value, (dict, list))
    )

    if records:
        table_header = "".join(f"<th>{escape(column)}</th>" for column in columns)
        table_rows = "\n".join(
            "<tr>"
            + "".join(f"<td>{escape(format_value(record.get(column)))}</td>" for column in columns)
            + "</tr>"
            for record in records
        )
        table = f"""
        <table>
          <thead><tr>{table_header}</tr></thead>
          <tbody>{table_rows}</tbody>
        </table>
        """
    else:
        table = '<div class="empty">No records were found in the JSON file.</div>'

    metadata_table = (
        f"""
        <h2>Summary</h2>
        <table class="metadata">
          <tbody>{metadata_rows}</tbody>
        </table>
        """
        if metadata_rows
        else ""
    )

    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {{
      margin: 0;
      padding: 24px;
      background: #f5f7fb;
      color: #172033;
      font-family: Arial, Helvetica, sans-serif;
      font-size: 14px;
    }}
    .container {{
      max-width: 980px;
      margin: 0 auto;
      background: #ffffff;
      border: 1px solid #d9e0ec;
      border-radius: 8px;
      overflow: hidden;
    }}
    .header {{
      padding: 22px 26px;
      background: #0f4c81;
      color: #ffffff;
    }}
    h1 {{
      margin: 0 0 8px;
      font-size: 22px;
      font-weight: 700;
    }}
    h2 {{
      margin: 24px 0 10px;
      font-size: 16px;
    }}
    .subtitle {{
      margin: 0;
      color: #dce9f7;
    }}
    .content {{
      padding: 22px 26px 28px;
    }}
    .stats {{
      display: inline-block;
      margin: 0 0 16px;
      padding: 8px 12px;
      background: #eef5fb;
      border: 1px solid #d5e5f3;
      border-radius: 6px;
      font-weight: 700;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      margin-top: 10px;
    }}
    th, td {{
      padding: 9px 10px;
      border: 1px solid #dfe6ef;
      text-align: left;
      vertical-align: top;
      word-break: break-word;
    }}
    th {{
      background: #eef2f7;
      color: #26364f;
      font-weight: 700;
    }}
    tr:nth-child(even) td {{
      background: #fafbfd;
    }}
    .metadata th {{
      width: 220px;
    }}
    .empty {{
      padding: 16px;
      background: #fff8e6;
      border: 1px solid #f0d58c;
      border-radius: 6px;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>{escape(title)}</h1>
      <p class="subtitle">Source: {escape(source_path)} | Generated: {escape(generated_at)}</p>
    </div>
    <div class="content">
      <div class="stats">Records: {len(records)}</div>
      {metadata_table}
      <h2>Details</h2>
      {table}
    </div>
  </div>
</body>
</html>
"""


def render_plain_report(title: str, records: Sequence[Dict[str, Any]], metadata: Dict[str, Any]) -> str:
    lines = [title, "", f"Records: {len(records)}"]
    if metadata:
        lines.append("")
        lines.append("Summary:")
        for key, value in metadata.items():
            if not isinstance(value, (dict, list)):
                lines.append(f"{key}: {format_value(value)}")

    lines.append("")
    lines.append("Details:")
    lines.append(json.dumps(records, indent=2, ensure_ascii=False))
    return "\n".join(lines)


def escape(value: Any) -> str:
    return html.escape(format_value(value), quote=True)


def build_message(
    config: Config,
    recipients: Sequence[str],
    subject: str,
    plain_body: str,
    html_body: str,
) -> MIMEMultipart:
    message = MIMEMultipart("alternative")
    if config.sender.name:
        message["From"] = f"{config.sender.name} <{config.sender.email}>"
    else:
        message["From"] = config.sender.email
    message["To"] = ", ".join(recipients)
    message["Subject"] = subject
    message.attach(MIMEText(plain_body, "plain", "utf-8"))
    message.attach(MIMEText(html_body, "html", "utf-8"))
    return message


def resolve_recipients(args: argparse.Namespace, config: Config) -> List[str]:
    recipients = args.recipients or config.default_recipients
    if not recipients:
        raise ValueError("No recipients were provided. Use --recipient or default_recipients in config.yaml.")
    return recipients


def send_smtp(config: Config, env: Dict[str, str], message: MIMEMultipart, recipients: Sequence[str]) -> None:
    password = env.get(config.smtp.password_env) if config.smtp.password_env else None
    username = config.smtp.username or config.sender.email

    if config.smtp.ssl:
        with smtplib.SMTP_SSL(config.smtp.host, config.smtp.port) as server:
            if password:
                server.login(username, password)
            server.sendmail(message["From"], list(recipients), message.as_string())
        return

    with smtplib.SMTP(config.smtp.host, config.smtp.port) as server:
        server.ehlo()
        if config.smtp.tls:
            server.starttls()
            server.ehlo()
        if password:
            server.login(username, password)
        server.sendmail(message["From"], list(recipients), message.as_string())


def main() -> int:
    args = parse_args()
    config = Config.load(args.config)
    env = load_env(args.env)

    data = load_json(args.input)
    records, metadata = extract_records(data, args.records_key)
    title = args.title or args.subject
    html_body = render_html_report(title, args.input, records, metadata)
    plain_body = render_plain_report(title, records, metadata)
    recipients = resolve_recipients(args, config)

    if args.output_html:
        Path(args.output_html).write_text(html_body, encoding="utf-8")
        print(f"HTML report written to: {args.output_html}")

    if args.dry_run:
        print(f"Dry run: report built for {len(records)} records.")
        print(f"Recipients: {', '.join(recipients)}")
        return 0

    provider = config.provider.lower()
    if provider not in {"smtp", "office365", "gmail", "google-workspace"}:
        print(f"Error: provider '{config.provider}' is not supported by this report sender.", file=sys.stderr)
        return 2

    message = build_message(config, recipients, args.subject, plain_body, html_body)
    send_smtp(config, env, message, recipients)
    print(f"Sent HTML report to: {', '.join(recipients)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
