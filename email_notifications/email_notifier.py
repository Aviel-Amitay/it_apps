#!/usr/bin/env python3

"""
Flexible notification framework for JSON-driven email delivery.
Supports SMTP providers, sendmail/postfix, debug mode, per-user and one-email modes.
"""

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import dotenv
except ImportError:
    dotenv = None


APP_DIR = Path(__file__).resolve().parent
ROOT_DIR = APP_DIR.parent
DEFAULT_CONFIG_FILE = APP_DIR / 'config.yaml'
DEFAULT_ENV_FILE = ROOT_DIR / '.env'
DEFAULT_LOG_FILE = ROOT_DIR / 'logs' / 'email_notifier.log'

# -----------------------------------------------------------------------------
# Models
# -----------------------------------------------------------------------------

@dataclass
class SenderConfig:
    email: str
    name: Optional[str] = None


@dataclass
class SMTPConfig:
    host: str
    port: int = 587
    tls: bool = True
    ssl: bool = False
    username: Optional[str] = None
    password_env: Optional[str] = None


@dataclass
class EmailAddressingConfig:
    type: str = 'first_name_dot_last_name'
    domain: Optional[str] = None
    email_field: Optional[str] = 'email'


@dataclass
class Config:
    provider: str = 'office365'
    sender: SenderConfig = field(default_factory=lambda: SenderConfig(email=''))
    smtp: SMTPConfig = field(default_factory=lambda: SMTPConfig(host='localhost'))
    email_addressing: EmailAddressingConfig = field(default_factory=EmailAddressingConfig)
    send_mode: str = 'one_email'
    body_type: str = 'plain'
    log_path: str = str(DEFAULT_LOG_FILE)
    default_recipients: List[str] = field(default_factory=list)
    debug_recipient: Optional[str] = None

    @classmethod
    def load(cls, path: str) -> 'Config':
        try:
            import yaml
        except ImportError as exc:
            raise RuntimeError("Missing Python dependency: PyYAML. Install it with: python -m pip install -r initial-project/requirements.txt") from exc

        with open(path, 'r') as stream:
            raw = yaml.safe_load(stream) or {}

        conf = cls()
        conf.provider = raw.get('provider', conf.provider)

        sender = raw.get('sender', {})
        conf.sender = SenderConfig(
            email=sender.get('email', ''),
            name=sender.get('name')
        )

        smtp = raw.get('smtp', {})
        conf.smtp = SMTPConfig(
            host=smtp.get('host', 'localhost'),
            port=smtp.get('port', 587),
            tls=smtp.get('tls', True),
            ssl=smtp.get('ssl', False),
            username=smtp.get('username'),
            password_env=smtp.get('password_env')
        )

        email_addressing = raw.get('email_addressing') or raw.get('email_format', {})
        conf.email_addressing = EmailAddressingConfig(
            type=email_addressing.get('type', conf.email_addressing.type),
            domain=email_addressing.get('domain'),
            email_field=email_addressing.get('email_field', conf.email_addressing.email_field)
        )

        conf.send_mode = raw.get('send_mode', conf.send_mode)
        conf.body_type = raw.get('body_type', conf.body_type)
        conf.log_path = raw.get('log_path', conf.log_path)
        conf.default_recipients = raw.get('default_recipients', conf.default_recipients)
        conf.debug_recipient = raw.get('debug_recipient')

        return conf


@dataclass
class UserEntry:
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    username: Optional[str] = None
    email: Optional[str] = None
    custom: Dict[str, Any] = field(default_factory=dict)
    payload: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, raw: Dict[str, Any]) -> 'UserEntry':
        return cls(
            first_name=raw.get('first_name'),
            last_name=raw.get('last_name'),
            username=raw.get('username'),
            email=raw.get('email'),
            custom={k: v for k, v in raw.items() if k not in {'first_name', 'last_name', 'username', 'email', 'projects'}},
            payload=raw
        )


@dataclass
class Summary:
    source: str
    action: Optional[str] = None
    subject: Optional[str] = None
    send_mode: Optional[str] = None
    recipients: List[str] = field(default_factory=list)
    body_type: Optional[str] = None
    body: Optional[str] = None
    users: List[UserEntry] = field(default_factory=list)
    raw: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def load(cls, path: str) -> 'Summary':
        with open(path, 'r') as stream:
            raw = json.load(stream)

        summary = cls(
            source=raw.get('source', ''),
            action=raw.get('action'),
            subject=raw.get('subject'),
            send_mode=raw.get('send_mode'),
            recipients=raw.get('recipients', []),
            body_type=raw.get('body_type'),
            body=raw.get('body'),
            raw=raw
        )

        users = raw.get('users', [])
        if isinstance(users, list):
            for user_raw in users:
                summary.users.append(UserEntry.from_dict(user_raw))

        return summary


# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------

EMAIL_FORMAT_GENERATORS = {
    'first_name_dot_last_name': lambda user, domain: f"{user.first_name.lower()}.{user.last_name.lower()}@{domain}" if user.first_name and user.last_name else None,
    'first_name_last_initial': lambda user, domain: f"{user.first_name.lower()}{user.last_name[0].lower()}@{domain}" if user.first_name and user.last_name else None,
    'first_initial_last_name': lambda user, domain: f"{user.first_name[0].lower()}{user.last_name.lower()}@{domain}" if user.first_name and user.last_name else None,
    'username': lambda user, domain: f"{user.username.lower()}@{domain}" if user.username else None,
}


def safe_lower(text: Optional[str]) -> Optional[str]:
    return text.lower() if text else None


def format_email_address(user: UserEntry, config: Config) -> Optional[str]:
    if config.email_addressing.type == 'custom_field':
        field = config.email_addressing.email_field
        return user.payload.get(field)

    if user.email:
        return user.email

    generator = EMAIL_FORMAT_GENERATORS.get(config.email_addressing.type)
    if not generator:
        return None

    domain = config.email_addressing.domain
    if not domain:
        return None

    return generator(user, domain)


def load_env(path: Optional[str] = None) -> Dict[str, str]:
    env_path = path or '.env'
    if os.path.exists(env_path):
        if dotenv:
            dotenv.load_dotenv(env_path)
        else:
            with open(env_path, 'r') as stream:
                for line in stream:
                    line = line.strip()
                    if not line or line.startswith('#') or '=' not in line:
                        continue
                    key, value = line.split('=', 1)
                    os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    return dict(os.environ)


def build_message(subject: str, from_addr: str, to_addr: str, plain_body: str, html_body: Optional[str] = None) -> MIMEMultipart:
    message = MIMEMultipart('alternative')
    message['From'] = from_addr
    message['To'] = to_addr
    message['Subject'] = subject

    message.attach(MIMEText(plain_body, 'plain'))
    if html_body:
        message.attach(MIMEText(html_body, 'html'))

    return message


def build_plain_body(summary: Summary, user: Optional[UserEntry] = None, config: Config = None) -> str:
    if user and summary.users:
        return json.dumps(user.payload, indent=2)
    if summary.body:
        return summary.body
    return json.dumps(summary.raw, indent=2)


def build_html_body(summary: Summary, user: Optional[UserEntry] = None, config: Config = None) -> str:
    plain = build_plain_body(summary, user, config)
    return f"<pre>{plain}</pre>"


def resolve_recipients(summary: Summary, config: Config) -> List[str]:
    if effective_send_mode(summary, config) == 'one_email':
        if summary.recipients:
            return summary.recipients
        return config.default_recipients
    return []


def effective_send_mode(summary: Summary, config: Config) -> str:
    return summary.send_mode or config.send_mode


def log_message(message: str, path: str) -> None:
    log_file = Path(path)
    if not log_file.is_absolute():
        log_file = ROOT_DIR / log_file
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=str(log_file), level=logging.INFO, format='%(asctime)s %(message)s')
    logging.info(message)


# -----------------------------------------------------------------------------
# Sender implementations
# -----------------------------------------------------------------------------

class Notifier:
    def __init__(self, config: Config, env: Dict[str, str]):
        self.config = config
        self.env = env

    def send(self, summary: Summary) -> int:
        provider = self.config.provider.lower()
        if provider in {'smtp', 'office365', 'gmail', 'google-workspace'}:
            return self._send_smtp(summary)
        if provider in {'sendmail', 'postfix'}:
            return self._send_sendmail(summary)
        if provider == 'debug':
            return self._send_debug(summary)

        raise ValueError(f"Unsupported provider: {provider}")

    def _build_from_address(self) -> str:
        if self.config.sender.name:
            return f"{self.config.sender.name} <{self.config.sender.email}>"
        return self.config.sender.email

    def _send_smtp(self, summary: Summary) -> int:
        password = None
        if self.config.smtp.password_env:
            password = self.env.get(self.config.smtp.password_env)

        recipients = []
        if effective_send_mode(summary, self.config) == 'per_user':
            for user in summary.users:
                email_address = format_email_address(user, self.config)
                if not email_address:
                    continue

                plain_body = build_plain_body(summary, user, self.config)
                html_body = build_html_body(summary, user, self.config) if self.config.body_type == 'table' else None
                message = build_message(summary.subject or 'Notification', self._build_from_address(), email_address, plain_body, html_body)
                self._smtp_send(message, email_address, password)
                recipients.append(email_address)

            log_message(f"Sent per-user notifications to: {recipients}", self.config.log_path)
            return len(recipients)

        recipients = resolve_recipients(summary, self.config)
        if not recipients:
            return 0

        plain_body = build_plain_body(summary, None, self.config)
        html_body = build_html_body(summary, None, self.config) if self.config.body_type == 'table' else None
        message = build_message(summary.subject or 'Notification', self._build_from_address(), ', '.join(recipients), plain_body, html_body)
        self._smtp_send(message, recipients, password)
        log_message(f"Sent one_email notification to: {recipients}", self.config.log_path)
        return len(recipients)

    def _smtp_send(self, message: MIMEMultipart, recipients: Any, password: Optional[str]) -> None:
        if self.config.smtp.ssl:
            import smtplib
            with smtplib.SMTP_SSL(self.config.smtp.host, self.config.smtp.port) as server:
                if self.config.smtp.tls:
                    server.ehlo()
                if password:
                    server.login(self.config.smtp.username or self.config.sender.email, password)
                server.sendmail(message['From'], recipients, message.as_string())
        else:
            import smtplib
            with smtplib.SMTP(self.config.smtp.host, self.config.smtp.port) as server:
                server.ehlo()
                if self.config.smtp.tls:
                    server.starttls()
                    server.ehlo()
                if password:
                    server.login(self.config.smtp.username or self.config.sender.email, password)
                server.sendmail(message['From'], recipients, message.as_string())

    def _send_sendmail(self, summary: Summary) -> int:
        recipients = []
        if effective_send_mode(summary, self.config) == 'per_user':
            for user in summary.users:
                email_address = format_email_address(user, self.config)
                if not email_address:
                    continue
                message = build_message(summary.subject or 'Notification', self._build_from_address(), email_address, build_plain_body(summary, user, self.config), None)
                self._sendmail(message, email_address)
                recipients.append(email_address)
            log_message(f"Sent per-user sendmail notifications to: {recipients}", self.config.log_path)
            return len(recipients)

        recipients = resolve_recipients(summary, self.config)
        if not recipients:
            return 0
        message = build_message(summary.subject or 'Notification', self._build_from_address(), ', '.join(recipients), build_plain_body(summary, None, self.config), None)
        self._sendmail(message, recipients)
        log_message(f"Sent one_email sendmail notification to: {recipients}", self.config.log_path)
        return len(recipients)

    def _sendmail(self, message: MIMEMultipart, recipients: Any) -> None:
        import subprocess
        proc = subprocess.Popen(['/usr/sbin/sendmail', '-t', '-oi'], stdin=subprocess.PIPE)
        proc.communicate(message.as_bytes())
        if proc.returncode != 0:
            raise RuntimeError(f"sendmail failed with code {proc.returncode}")

    def _send_debug(self, summary: Summary) -> int:
        if self.config.debug_recipient:
            recipient = self.config.debug_recipient
            print(f"DEBUG send to {recipient}")
            if effective_send_mode(summary, self.config) == 'per_user':
                for user in summary.users:
                    print(f"--- User: {user.first_name} {user.last_name} ({recipient}) ---")
                    print(build_plain_body(summary, user, self.config))
                return len(summary.users)

            print(build_plain_body(summary, None, self.config))
            return 1

        if effective_send_mode(summary, self.config) == 'per_user':
            for user in summary.users:
                email_address = format_email_address(user, self.config)
                if not email_address:
                    continue
                print(f"DEBUG send to {email_address}")
                print(build_plain_body(summary, user, self.config))
            return len(summary.users)

        recipients = resolve_recipients(summary, self.config)
        print(f"DEBUG send to {recipients}")
        print(build_plain_body(summary, None, self.config))
        return len(recipients)


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Flexible JSON-driven email notifier.')
    parser.add_argument('-c', '--config', default=str(DEFAULT_CONFIG_FILE), help='Notification config file')
    parser.add_argument('-e', '--env', default=str(DEFAULT_ENV_FILE), help='Environment file with secrets')
    parser.add_argument('-s', '--summary', help='Summary JSON file produced by caller')
    parser.add_argument('-r', '--recipient', action='append', dest='recipients', help='Override one_email recipients. Can be used more than once')
    parser.add_argument('--send-test', action='store_true', help='Send a test email using the current configuration')
    parser.add_argument('--debug', action='store_true', help='Run in debug mode')
    parser.add_argument('--dry-run', action='store_true', help='Do not send email, only print actions')
    return parser.parse_args()


def build_test_summary(config: Config) -> Summary:
    recipients = config.default_recipients or [config.sender.email]
    return Summary(
        source='email_notifier',
        action='test_email',
        subject='Notification framework test',
        send_mode='one_email',
        recipients=recipients,
        body_type='plain',
        body='This is a test notification from email_notifier.py.',
        raw={'type': 'test', 'timestamp': datetime.utcnow().isoformat()}
    )


def main() -> int:
    args = parse_args()
    config = Config.load(args.config)
    env = load_env(args.env)

    if not args.summary and not args.send_test:
        print('Error: either --summary or --send-test must be provided.', file=sys.stderr)
        return 1

    if args.send_test:
        summary = build_test_summary(config)
    else:
        summary = Summary.load(args.summary)

    if args.recipients:
        summary.recipients = args.recipients
        summary.send_mode = 'one_email'

    if args.debug:
        config.provider = 'debug'

    notifier = Notifier(config, env)

    try:
        recipients_count = notifier.send(summary)
    except Exception as exc:
        error_message = str(exc)
        print(f"Error sending notification: {error_message}", file=sys.stderr)
        print('Please review email_notifications/config.yaml and .env, then run initial-project/setup_email_config.sh again if needed.', file=sys.stderr)
        return 2

    if args.dry_run:
        print('Dry run enabled — no email was actually sent.')

    print(f"Notifications processed: {recipients_count}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
