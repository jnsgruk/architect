#!/bin/bash 
set -euo pipefail
# Output green message prefixed with [+]
_info() { echo -e "\e[92m[+] ${1:-}\e[0m"; }
# Output orange message prefixed with [-]
_warn() { echo -e "\e[33m[-] ${1:-}\e[0m"; }
# Output red message prefixed with [!] and exit
_error() { echo -e >&2 "\e[31m[!] ${1:-}\e[0m"; exit 1; }

_bootstrap() {
  # Check for internet access and bail out if there isn't any!
  if ! _check_online; then _error "Please connect to the internet"; fi
  _install_yq
  # Configure architect
  _info "Configuring architect installer"
  _configure
  _set_debug
  # Install git
  _info "Installing git into live environment"
  pacman -Syy --noconfirm git
  # Clone the rest of architect
  _info "Fetching latest version of architect"
  git clone --depth 1 -b "$(_config_value architect.branch)" https://github.com/jnsgruk/architect /architect
  # Copy the config into the architect directory
  cp "${CONFIG}" /architect/config.yml
  # Reset the config variable to use the new path from now on
  export CONFIG="/architect/config.yml"
  # Start stage 1 installer
  /bin/bash /architect/stage1.sh
}

_set_debug() {
  # Enable debug mode if
  if command -v yq >/dev/null && [[ "$(_config_value architect.debug)" == "true" ]]; then
    set -x
  fi
}

_install_yq() {
  # Download yq to parse config file
  _info "Fetching yq tool to parse config"
  curl -sLo /usr/bin/yq https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64
  chmod 755 /usr/bin/yq
}

_configure() {
  required_fields=(
    hostname
    username
    regional.locale
    regional.timezone
    regional.keymap
    partitioning.disk
    partitioning.filesystem
    partitioning.encrypted
    architect.branch
    architect.disable_stage3
  )

  for v in "${required_fields[@]}"; do
    value=$(_config_value "$v")
    [[ -z "${value}" ]] && _error "Undefined config value: ${v}"
  done
  _info "Validated config"
}

_config_value() {
  # Ensure there is an argument passed to the function
  if [[ -z "${1:-}" ]]; then _error "_config_value requires an argument (path to config value)"; fi
  # Try to read the value from the current config
  value=$(yq r "${CONFIG}" "${1}")
  # If the value is empty...
  if [[ -z "${value}" ]]; then
    # Try to read the value from the default config
    value=$(yq r "$(_find_default_config)" "${1}")
    # If the value is still emtpy, bail out
    if [[ -z "${value}" ]]; then
      _error "Undefined config value for ${1}"
    fi
  fi
  # "Return" the value
  echo "${value}"
}

_config_list() {
  # Ensure there is an argument passed to the function
  if [[ -z "${1:-}" ]]; then _error "_config_list requires an argument (path to config value)"; fi
  # Get the list as a space seperated string
  list="$(yq r "${CONFIG}" "${1}[*]" | tr '\n' ' ')"
  echo "${list}"
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

_find_default_config() {
  script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

  if [[ -f "/architect/presets/default.yml" ]]; then
    echo "/architect/presets/default.yml"
  elif [[ -f "${script_dir}/presets/default.yml" ]]; then
    echo "${script_dir}/presets/default.yml"
  elif curl -fsLo /tmp/architect.yml "https://raw.githubusercontent.com/jnsgruk/architect/master/presets/default.yml"; then
    echo "/tmp/architect.yml"
  else
    _error "Could not find or download default config, please specify config as first argument and re-run this script"
  fi
}

# Check if config is already defined; skip this step if it is
if [[ -z "${CONFIG:-}" ]]; then
  # Remove any old (downloaded) config files
  rm -f /tmp/architect.yml
  if [[ -n "${1:-}" ]]; then
    # If the first argument is a file, then set CONFIG to the filename
    if [[ -f "${1}" ]]; then
      CONFIG="${1}"
      _info "Using config specified at: ${1}"
    
    # Check if there is an Architect preset matching the first arg
    elif curl -fsLo "/tmp/architect.yml" "https://raw.githubusercontent.com/jnsgruk/architect/master/presets/${1}.yml"; then
      CONFIG="/tmp/architect.yml"
      _info "Using architect preset config: ${1}"
    
    # Check if the specified argument is a valid URL to a user config
    elif curl -fsLo /tmp/architect.yml "${1}"; then
      CONFIG="/tmp/architect.yml"
      _info "Using config specified at: ${1}"
    
    # Unrecognised argument, try to get the default config
    else
      CONFIG="$(_find_default_config)"
      _warn "No valid config specified, using defaults at ${CONFIG}"
    fi
  else
    # No arguments specified, use the default config
    CONFIG="$(_find_default_config)"
    _warn "No config specified, using defaults at ${CONFIG}"
  fi
  export CONFIG
fi

# Enable debug mode if specifed in config
_set_debug

# Check if architect is already in the environment
# If not, we need to bootstrap
if [[ ! -d /architect ]]; then
  _bootstrap
fi