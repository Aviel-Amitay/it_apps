#!/usr/bin/env bash

# Setup helper for email notification configuration.
# Writes config.yaml and .env based on interactive answers.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
EMAIL_APP_DIR="$PROJECT_ROOT/email_notifications"
CONFIG_FILE="$EMAIL_APP_DIR/config.yaml"
ENV_FILE="$PROJECT_ROOT/.env"

prompt() {
  local message="$1"
  local default="$2"
  local answer

  if [[ -n "$default" ]]; then
    read -rp "$message [$default]: " answer
    echo "${answer:-$default}"
  else
    read -rp "$message: " answer
    echo "$answer"
  fi
}

print_header() {
  echo
  echo "========================================"
  echo " Email Notification Setup Configuration  "
  echo "========================================"
  echo
}

ask_confirm() {
  local message="$1"
  local default="$2"
  local answer

  while true; do
    read -rp "$message [$default]: " answer
    answer="${answer:-$default}"
    if [[ "$answer" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      return 0
    elif [[ "$answer" =~ ^([nN][oO]|[nN])$ ]]; then
      return 1
    else
      echo "Please answer yes or no." >&2
    fi
  done
}

choice_prompt() {
  local prompt_message="$1"
  local default_index="$2"
  shift 2
  local options=("$@")
  local answer
  local value

  while true; do
    echo >&2
    echo "$prompt_message" >&2
    local index=1
    for opt in "${options[@]}"; do
      echo "  $index) $opt" >&2
      ((index++))
    done
    echo >&2

    read -rp "Choose an option number [${default_index}]: " answer
    answer="${answer:-$default_index}"

    if ! [[ "$answer" =~ ^[0-9]+$ ]]; then
      echo "Invalid selection: '$answer'. Please enter a number between 1 and ${#options[@]}." >&2
      continue
    fi

    if (( answer < 1 || answer > ${#options[@]} )); then
      echo "Invalid selection: '$answer'. Please enter a number between 1 and ${#options[@]}." >&2
      continue
    fi

    value="${options[$((answer-1))]}"

    if ask_confirm "You selected '$value'. Is that correct?" yes; then
      echo "$value"
      return
    fi
  done
}

input_prompt() {
  local prompt_message="$1"
  local default="$2"
  local answer

  while true; do
    echo >&2
    read -rp "$prompt_message [$default]: " answer
    answer="${answer:-$default}"

    if ask_confirm "You entered '$answer'. Is that correct?" yes; then
      echo "$answer"
      return
    fi
  done
}

print_header

provider="$(choice_prompt 'Provider choices:' '1' 'office365' 'gmail' 'google-workspace' 'on-prem-smtp' 'debug')"
sender_email="$(input_prompt 'Sender email' 'devops@example.com')"
sender_name="$(input_prompt 'Sender name' 'DevOps Automation')"
email_addressing_type="$(choice_prompt 'Email addressing options:' '1' 'first_name_dot_last_name' 'first_name_last_initial' 'first_initial_last_name' 'username' 'custom_field')"

if [[ "$email_addressing_type" == 'custom_field' ]]; then
  echo
  echo 'Custom field means your summary JSON provides the full email address directly.'
  echo 'Example user entry:'
  echo '  { "first_name": "Aviel", "last_name": "Amitay", "email": "aviela@example.com" }'
fi

domain="$(input_prompt 'Email domain for generated addresses' 'example.com')"
email_field="$(input_prompt 'Custom email field name (for custom_field)' 'email')"

smtp_host=""
smtp_port=""
smtp_tls=""
smtp_ssl=""
username=""
password_env=""

case "$provider" in
  office365)
    default_smtp_host="smtp.office365.com"
    default_smtp_port="587"
    default_smtp_tls="true"
    default_smtp_ssl="false"
    ;;
  gmail|google-workspace)
    default_smtp_host="smtp.gmail.com"
    default_smtp_port="587"
    default_smtp_tls="true"
    default_smtp_ssl="false"
    ;;
  on-prem-smtp)
    default_smtp_host="smtp.example.com"
    default_smtp_port="25"
    default_smtp_tls="false"
    default_smtp_ssl="false"
    ;;
esac

if [[ "$provider" == "on-prem-smtp" || "$provider" == "office365" || "$provider" == "gmail" || "$provider" == "google-workspace" ]]; then
  smtp_host="$(prompt 'SMTP host' "$default_smtp_host")"
  smtp_port="$(prompt 'SMTP port' "$default_smtp_port")"
  smtp_tls="$(prompt 'Use TLS (true/false)' "$default_smtp_tls")"
  smtp_ssl="$(prompt 'Use SSL (true/false)' "$default_smtp_ssl")"
  username="$(prompt 'SMTP username' "$sender_email")"
  password_env="SMTP_PASSWORD"
fi

debug_recipient="$(prompt 'Debug recipient email (optional)' '')"

cat > "$CONFIG_FILE" <<EOF
provider: $provider

sender:
  email: "$sender_email"
  name: "$sender_name"

smtp:
  host: "$smtp_host"
  port: $smtp_port
  tls: $smtp_tls
  ssl: $smtp_ssl
  username: "$username"
  password_env: "$password_env"

email_addressing:
  type: "$email_addressing_type"
  domain: "$domain"
  email_field: "$email_field"

send_mode: per_user
body_type: plain
log_path: "logs/email_notifier.log"

default_recipients:
  - "$sender_email"
debug_recipient: "$debug_recipient"
EOF

if [[ -n "$password_env" && ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<EOF
# Sensitive SMTP credentials
$password_env=""
EOF
  echo "Created $ENV_FILE. Fill in the secret values before using email_notifier.py."
elif [[ -z "$password_env" ]]; then
  echo "No SMTP secret is required for provider '$provider'."
else
  echo "$ENV_FILE already exists. Please update it with secrets as needed."
fi

echo "Created $CONFIG_FILE"
echo "Setup complete. Run email_notifier.py --help for usage."

do_test="$(prompt 'Send a test email now? (yes/no)' 'yes')"
if [[ "$do_test" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import yaml, dotenv' >/dev/null 2>&1; then
      echo "Missing Python dependencies. Install them with: python -m pip install -r initial-project/requirements.txt" >&2
      exit 1
    fi
    echo "Sending test email..."
    if ! python3 "$EMAIL_APP_DIR/email_notifier.py" --config "$CONFIG_FILE" --env "$ENV_FILE" --send-test; then
      echo "Test email failed. Please update $CONFIG_FILE or $ENV_FILE and rerun this script." >&2
    else
      echo "Test email sent successfully. Configuration is valid."
    fi
  else
    echo "python3 is not available in PATH. Please install Python 3 or run email_notifier.py manually." >&2
  fi
fi
