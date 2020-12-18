#!/bin/bash 

set -euxo pipefail
# Output green message prefixed with [+]
_info() { echo -e "\e[92m[+] ${1:-}\e[0m"; }
# Output orange message prefixed with [-]
_warn() { echo -e "\e[33m[-] ${1:-}\e[0m"; }
# Output red message prefixed with [!] and exit
_error() { echo -e >&2 "\e[31m[!] ${1:-}\e[0m"; exit 1; }

_bootstrap() {
  # Check for internet access and bail out if there isn't any!
  if ! _check_online; then _error "Please connect to the internet"; fi
  # Install git
  _info "Installing git into live environment"
  pacman -Syy --noconfirm git
  # Clone the rest of architect
  _info "Fetching latest version of architect"
  git clone --depth 1 -b "${ARCHITECT_BRANCH:-master}" https://github.com/jnsgruk/architect /architect
  # Configure architect
  _info "Configuring architect"
  _configure
  # Start stage 1 installer
  /bin/bash /architect/stage1.sh
}

_configure() {
  export DISK="${DISK:-/dev/vda}"
  export TZ="${TZ:-Europe/London}"
  export LOCALE="${LOCALE:-en_GB.UTF-8}"
  export KEYMAP="${KEYMAP:-uk}"
  export NEWHOSTNAME="${NEWHOSTNAME:-archie}"
  export NEWUSER="${NEWUSER:-jon}"
  export ENCRYPTED="${ENCRYPTED:-false}"
  export FILESYSTEM="${FILESYSTEM:-ext4}"
  export DISABLE_STAGE3="${DISABLE_STAGE3:-}"
}

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

# Check if architect is already in the environment
# If not, we need to bootstrap
if [[ ! -d /architect ]]; then
  _bootstrap
fi