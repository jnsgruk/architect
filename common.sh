#!/bin/bash 

set -euxo pipefail
# Output green message prefixed with [+]
_info() { echo -e "\e[92m[+] ${1:-}\e[0m"; }
# Output orange message prefixed with [-]
_warn() { echo -e "\e[33m[-] ${1:-}\e[0m"; }
# Output red message prefixed with [!] and exit
_error() { echo -e >&2 "\e[31m[!] ${1:-}\e[0m"; exit 1; }

_check_efi() {
  # Check if there are any efi variables
  if [[ -d /sys/firmware/efi ]]; then
    return 0
  else
    return 1
  fi
}

_check_online() {
  _info "Checking for an internet connection"
  if curl -s ifconfig.co >/dev/null; then
    return 0
  else
    return 1
  fi
}