#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  
  _setup_yay
  _cleanup
}

_setup_yay() {
  _info "Creating a build user for makepkg"
  # Create a build user with no home directory, and no login shell
  useradd -m -s /bin/nologin -r architect 
  # Ensure the build user can sudo without passwd
  echo "architect ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-architect-build
  chmod 600 /etc/sudoers.d/99-architect-build
  _info "Installing yay"
  # Clone yay
  sudo -u architect git clone --depth 1 https://aur.archlinux.org/yay.git /tmp/yay
  # Build and install yay
  cd /tmp/yay || exit 1
  sudo -u architect makepkg -si --noconfirm
  cd / || exit 1
}

_cleanup() {
  _info "Cleaning up build user and sudo config"
  rm -rf /etc/sudoers.d/99-architect-build
  userdel -rf architect
}

_main