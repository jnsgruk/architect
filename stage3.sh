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
  # Get desktop environment configuration
  desktop="$(_config_value provisioning.desktop)"

  if [[ "${desktop}" =~ ^gnome|plasma|xfce|mate$ ]]; then
    extras="$(_config_value provisioning.desktop-extras)"  
    
    # Install and configure Xorg/graphics drivers
    _install_xorg_drivers

    # Install and configure the desktop environment
    if [[ "${desktop}" == "gnome" ]]; then
      _info "Installing Gnome"
      # Install basic Gnome and GDM packages
      pacman -S --noconfirm gnome gdm gnome-terminal
      # Install the extras if specified
      if [[ "${extras}" == "true" ]]; then
        pacman -S --noconfirm gnome-extras
      fi
      # Enable the display manager on boot
      systemctl enable gdm
    elif [[ "${desktop}" == "plasma" ]]; then
      _info "Installing Plasma"
      # Install basic Plasma and SDDM packages
      pacman -S --noconfirm plasma-meta sddm konsole
      # Install the extras if specified
      if [[ "${extras}" == "true" ]]; then
        pacman -S --noconfirm kde-applications
      fi
      # Enable the display manager on boot
      systemctl enable sddm
    elif [[ "${desktop}" == "xfce" ]]; then
      _info "Installing XFCE"
      # Install basic XFCE and LightDM packages
      pacman -S --noconfirm xfce4 lightdm lightdm-webkit2-greeter
      # Install the extras if specified
      if [[ "${extras}" == "true" ]]; then
        pacman -S --noconfirm xfce4-goodies
      fi
      # Enable the display manager on boot
      systemctl enable lightdm
    elif [[ "${desktop}" == "mate" ]]; then
      _info "Installing MATE"
      # Install basic MATE and LightDM packages
      pacman -S --noconfirm mate lightdm lightdm-webkit2-greeter
      # Install the extras if specified
      if [[ "${extras}" == "true" ]]; then
        pacman -S --noconfirm mate-extra
      fi
      # Enable the display manager on boot
      systemctl enable lightdm
    fi
  fi
}

_install_xorg_drivers() {
  # First detect the GPU type
  gpuinfo="$(lspci -v | grep -A1 -e VGA -e 3D)"

  if grep -i -q "qxl" <<<"${gpuinfo}"; then
    _info "QXL/Virtualised GPU detected"
    drivers=(spice-vdagent qemu-guest-agent)
  elif grep -i -q "intel" <<<"${gpuinfo}"; then
    _info "Intel GPU detected"
    drivers=(xf86-video-intel)
  elif grep -i -q "amd" <<<"${gpuinfo}"; then
    _info "AMD GPU detected"
    drivers=(xf86-video-amdgpu)
  elif grep -i -q "nvidia" <<<"${gpuinfo}"; then
    _info "nVidia GPU detected"
    drivers=(nvidia)
  fi
  # Install Xorg and video drivers
  _info "Installing Xorg and video drivers"
  pacman -S --noconfirm xorg-server "${drivers[@]}"

  # Enable spice-vdagent if QXL
  if grep -i -q "qxl" <<<"${gpuinfo}"; then
    _info "Enabling spice agent"
    systemctl enable spice-vdagentd
    systemctl enable qemu-guest-agent
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