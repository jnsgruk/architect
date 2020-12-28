#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  _install_base_packages
  _install_desktop
  _setup_yay
  _cleanup
}

_install_base_packages() {
  # Convert the yaml packages list into a bash array
  packages=($(_config_list provisioning.packages))
  if [[ "${#packages[@]}" -gt 0 ]]; then
    pacman -S --noconfirm "${packages[@]}"
  fi
}

_install_desktop() {
  desktop="$(_config_value provisioning.desktop)"
  extras="$(_config_value provisioning.desktop-extras)"

  if [[ "${desktop}" == "gnome" ]]; then
    _info "Installing Gnome"
    pacman -S --noconfirm gnome gdm
    if [[ "${extras}" == "true" ]]; then
      pacman -S --noconfirm gnome-extras
    fi
    systemctl enable gdm
  elif [[ "${desktop}" == "plasma" ]]; then
    _info "Installing Plasma"
    pacman -S --noconfirm plasma sddm
    if [[ "${extras}" == "true" ]]; then
      pacman -S --noconfirm kde-applications
    fi
    systemctl enable sddm
  elif [[ "${desktop}" == "xfce" ]]; then
    _info "Installing XFCE"
    pacman -S --noconfirm xfce4 lightdm lightdm-gtk-greeter
    if [[ "${extras}" == "true" ]]; then
      pacman -S --noconfirm xfce4-goodies
    fi
    systemctl enable lightdm
  elif [[ "${desktop}" == "mate" ]]; then
    _info "Installing MATE"
    pacman -S --noconfirm mate lightdm lightdm-gtk-greeter
    if [[ "${extras}" == "true" ]]; then
      pacman -S --noconfirm mate-extra
    fi
    systemctl enable lightdm
  fi
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