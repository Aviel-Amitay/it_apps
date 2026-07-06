# Email Notifications

This project sends HTML email reports from JSON files.

The main idea is:

```text
collector script -> report/*.json -> email_notifier.py -> email
```

If a JSON file already exists, send it with `email_notifier.py`.
If the JSON file does not exist yet, run `collector_script.py` first.

Run commands from the project root.  


## Files

| File | Purpose |
| --- | --- |
| `json_report_email.py` | Reads JSON, builds HTML, sends email |
| `email_notifier.py` | JSON-driven email notifier and shared SMTP helper logic |
| `config.yaml` | Email provider, SMTP server, sender, recipients |
| `config-example.yaml` | Sanitized example config |
| `.env` | SMTP password or app password, do not commit this file |
| `env-example` | Sanitized environment variable example |
| `report/*.json` | Generated JSON reports |
| `sample_report.html` | Example generated HTML output |
| `initial-project/setup_email_config.sh` | Interactive config setup helper |
| `initial-project/requirements.txt` | Python dependencies |
| `logs/` | Notification log files |

## Install

From the project root:

```bash
python3 -m venv venv
source venv/bin/activate
python -m pip install -r initial-project/requirements.txt
```

## Basic Test

Generate a dummy AWS report:

```bash
python email_notifications/collector_script.py --case aws --dummy
```

This creates:

```text
report/aws_report.json
```

Preview the email without sending:

```bash
python email_notifications/email_notifier.py \
  --summary report/aws_report.json \
  --recipient your_email@example.com \
  --debug
```

Expected result:

```text
DEBUG send to ...
Notifications processed: 1
```

Send a real email:

```bash
python email_notifications/email_notifier.py \
  --summary report/aws_report.json \
  --recipient your_email@example.com
```

## Gmail Connection

Use this config:

```yaml
provider: gmail

sender:
  email: "your_email@gmail.com"
  name: "DevOps Automation"

smtp:
  host: "smtp.gmail.com"
  port: 587
  tls: true
  ssl: false
  username: "your_email@gmail.com"
  password_env: "SMTP_PASSWORD"
```

Create `.env` in the project root:

```bash
SMTP_PASSWORD="your_google_app_password"
```

Important:

Gmail requires an App Password, not your regular Gmail password, in case you have 2-Step Verification active.

Steps:

1. Open Google Account
2. Navigate with this link directly to the `App passwords` https://myaccount.google.com/apppasswords
3. Enter your gmail / organization password.
5. Create a password for `Mail`
6. Put the generated password in `.env`

Common Gmail error:

```text
SMTPAuthenticationError: 534
Application-specific password required
```

Fix:

Use a Gmail App Password in `.env`.

## Office 365 Connection

Use this config:

```yaml
provider: office365

sender:
  email: "your_user@your_domain.com"
  name: "DevOps Automation"

smtp:
  host: "smtp.office365.com"
  port: 587
  tls: true
  ssl: false
  username: "your_user@your_domain.com"
  password_env: "SMTP_PASSWORD"
```

Create `.env` in the project root:

```bash
SMTP_PASSWORD="your_password_or_app_password"
```

Important checks:

1. SMTP AUTH must be enabled for the mailbox
2. The account must be allowed to send mail
3. MFA accounts may require an app password or another approved auth method
4. The sender address should usually match the authenticated username

Common Office 365 error:

```text
SMTPAuthenticationError: 535
Authentication unsuccessful
```

Fix:

Check the password, MFA, SMTP AUTH setting, and username.

## On-Prem SMTP Connection

Use this config when your company has an internal relay:

```yaml
provider: smtp

sender:
  email: "devops@company.local"
  name: "DevOps Automation"

smtp:
  host: "smtp.company.local"
  port: 25
  tls: false
  ssl: false
  username: ""
  password_env: ""
```

Usually internal SMTP relays work by source IP allowlist.
In that case, no username or password is required.

Important checks:

1. Your machine IP must be allowed by the SMTP relay
2. Default port is `25`, `587`, otherwise check with your local IT support
the company SMTP port must be reachable
3. The relay must allow the `From` address
4. Some relays block external recipients

Test network connection:

```bash
nc -vz smtp.company.local 25
```

## Debug Mode

Use `--debug` when you want to test logic without sending email.

This command does not send a real email:

```bash
python email_notifications/email_notifier.py \
  --summary report/aws_report.json \
  --recipient your_email@example.com \
  --debug
```

If `email_notifications/config.yaml` has this provider, nothing will be sent even without `--debug`:

```yaml
provider: debug
```

For real sending, use a real provider:

```yaml
provider: gmail
```

or:

```yaml
provider: office365
```

## Dummy Report Examples

Generate every dummy report:

```bash
python email_notifications/collector_script.py --case all --dummy
```

Generate one dummy report:

```bash
python email_notifications/collector_script.py --case aws --dummy
python email_notifications/collector_script.py --case chef --dummy
python email_notifications/collector_script.py --case project-users --dummy
python email_notifications/collector_script.py --case licenses --dummy
```

Send the AWS dummy report to your inbox:

```bash
python email_notifications/email_notifier.py \
  --summary report/aws_report.json \
  --recipient your_email@example.com
```

Preview the project-users dummy report on the terminal:

```bash
python email_notifications/email_notifier.py \
  --summary report/project_users_report.json \
  --debug
```

Project-user reports use `send_mode: per_user`, so each user record controls its own recipient address. For inbox testing, use `--debug` first or generate a project-user report with your own `--email`.

The `--recipient` flag overrides recipients inside JSON reports that use `send_mode: one_email`. It is useful because dummy reports may contain placeholder recipients such as `devops@example.com`.

## Real Project-User Example

Generate a project-user report with your own values:

```bash
python email_notifications/collector_script.py \
  --case project-users \
  --project my-project \
  --username aviela \
  --first-name Aviel \
  --last-name Amitay \
  --email aviela@example.com \
  --manager market1 \
  --status created
```

Preview it:

```bash
python email_notifications/email_notifier.py \
  --summary report/project_users_report.json \
  --debug
```

## JSON Input Format

The script supports common record keys automatically:

```text
users, items, data, results, rows, records
```

Example:

```json
{
  "source": "daily_check",
  "environment": "dev",
  "records": [
    {
      "server": "web01",
      "status": "ok",
      "disk_usage": "62%"
    },
    {
      "server": "db01",
      "status": "warning",
      "disk_usage": "88%"
    }
  ]
}
```

Run with this JSON from inside `email_notifications/`:

```bash
python3 json_report_email.py \
  --config config.yaml \
  --env ../.env \
  --input ../report/daily_report.json \
  --subject "Daily DevOps Report" \
  --title "Daily DevOps Report" \
  --recipient your_email@example.com \
  --output-html daily_report.html
```

If your records are under a custom key:

```json
{
  "servers_status": [
    {
      "server": "web01",
      "status": "ok"
    }
  ]
}
```

Use this from inside `email_notifications/`:

```bash
python3 json_report_email.py \
  --config config.yaml \
  --env ../.env \
  --input ../report/daily_report.json \
  --records-key servers_status \
  --subject "Daily DevOps Report" \
  --title "Daily DevOps Report" \
  --recipient your_email@example.com
```

## Collector Script

Create a collector script only when the JSON file does not already exist.

Example:

```python
#!/usr/bin/env python3

import json
from datetime import datetime

data = {
    "source": "daily_check",
    "generated_at": datetime.now().isoformat(),
    "records": [
        {
            "server": "web01",
            "status": "ok",
            "disk_usage": "62%"
        },
        {
            "server": "db01",
            "status": "warning",
            "disk_usage": "88%"
        }
    ]
}

with open("../report/daily_report.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
```

Run from inside `email_notifications/`:

```bash
python3 collector_script.py
```

Then send from inside `email_notifications/`:

```bash
python3 json_report_email.py \
  --config config.yaml \
  --env ../.env \
  --input ../report/daily_report.json \
  --subject "Daily DevOps Report" \
  --title "Daily DevOps Report" \
  --recipient your_email@example.com
```

## Full Wrapper Script

Use a wrapper script when you want one command to collect data and send email.

Example `run_daily_report.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

python3 collector_script.py

python3 json_report_email.py \
  --config config.yaml \
  --env ../.env \
  --input ../report/daily_report.json \
  --subject "Daily DevOps Report" \
  --title "Daily DevOps Report" \
  --recipient your_email@example.com \
  --output-html daily_report.html
```

Make it executable:

```bash
chmod +x run_daily_report.sh
```

Run:

```bash
./run_daily_report.sh
```

## Troubleshooting

| Error | Meaning | Fix |
| --- | --- | --- |
| `Application-specific password required` | Gmail rejected regular password | Use Gmail App Password |
| `Authentication unsuccessful` | SMTP login failed | Check username, password, MFA, SMTP AUTH |
| `Connection refused` | SMTP host or port is not reachable | Check host, port, firewall, VPN |
| `Name or service not known` | DNS cannot resolve SMTP host | Check SMTP hostname |
| `No recipients were provided` | No `--recipient` and no default recipients | Add `--recipient` or update `default_recipients` |
| `provider is not supported` | Unsupported provider in `config.yaml` | Use `gmail`, `office365`, `google-workspace`, or `smtp` |
| Empty or ugly report | JSON structure is different than expected | Use `--records-key your_key` |

## Security Notes

Do not commit `.env` to Git.

Add this to `.gitignore`:

```gitignore
.env
*.log
```

Do not place real passwords inside `config.yaml`.
Use `password_env` and keep the secret in `.env`.
