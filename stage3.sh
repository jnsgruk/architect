#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  # shellcheck source=architect.sh
  source /architect/architect.sh
  
  _install_base_packages
  _install_desktop
  _setup_yay
  _setup_plymouth
  _cleanup
}

_install_base_packages() {
  # Convert the yaml packages list into a bash array
  mapfile -t packages < <(_config_list provisioning.packages)
  if [[ "${#packages[@]}" -gt 0 ]]; then
    #shellcheck disable=SC2068
    pacman -S --noconfirm ${packages[@]}
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
        pacman -S --noconfirm gnome-extra
      fi
      # Enable the display manager on boot
      systemctl enable gdm
    elif [[ "${desktop}" == "plasma" ]]; then
      _info "Installing Plasma"
      # Install basic Plasma and SDDM packages
      pacman -S --noconfirm plasma-meta sddm konsole
      echo -e "[Theme]\nCurrent=breeze\n" > /etc/sddm.conf
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
      # Configure lightdm
      sed -i "s/#greeter-session=example-gtk-gnome/greeter-session=lightdm-webkit2-greeter/g" /etc/lightdm/lightdm.conf
      sed -i "s/#user-session=default/user-session=xfce/g" /etc/lightdm/lightdm.conf
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
      # Configure lightdm
      sed -i "s/#greeter-session=example-gtk-gnome/greeter-session=lightdm-webkit2-greeter/g" /etc/lightdm/lightdm.conf
      sed -i "s/#user-session=default/user-session=mate/g" /etc/lightdm/lightdm.conf
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
  # Install the xorg-drivers group
  local drivers=(xorg-drivers)
  
  if grep -i -q -E "qxl|virtio" <<<"${gpuinfo}"; then
    _info "QXL/Virtualised GPU detected"
    drivers+=(spice-vdagent qemu-guest-agent)
  elif grep -i -q "nvidia" <<<"${gpuinfo}"; then
    _info "nVidia GPU detected"
    drivers+=(nvidia)
  fi
  # Install Xorg and video drivers
  _info "Installing Xorg and video drivers"
  pacman -S --noconfirm xorg-server "${drivers[@]}"

  # Enable spice-vdagent if QXL
  if grep -i -q -E "qxl|virtio" <<<"${gpuinfo}"; then
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

# Wrapper function to install a package from the AUR with no prompts
# This is quite a dangerous function; you probably shouldn't use yay like this!
_install_aur() {
  sudo -u architect yay \
    --nodiffmenu \
    --noeditmenu \
    --nocleanmenu \
    --answerupgrade y \
    --noremovemake \
    -S --noconfirm "$@"
}

_setup_plymouth() {
  # Only run this code if plymouth was enabled
  if [[ "$(_config_value provisioning.plymouth)" == "true" ]]; then
    # Declare some local variables to use
    local desktop=""
    desktop="$(_config_value provisioning.desktop)"
    
    # Install plymouth
    _install_aur plymouth

    # GDM/Plymouth work better together with the gdm-plymouth package
    if [[ "${desktop}" == "gnome" ]]; then
      # Remove conflicting versions of gdm/libgdm before aur install
      pacman -Rd --nodeps --noconfirm gdm libgdm
      # Install the new version of gdm with plymouth integration
      _install_aur gdm-plymouth
      # Make sure gdm is enabled
      systemctl enable gdm
    fi
  
    # Install needed packages
    _install_aur "${aur_packages[@]}"

    # Import the helper functions from stage2
    # shellcheck source=stage2.sh
    source /architect/stage2.sh

    # Regenerate the initramfs with plymouth
    _setup_mkinitcpio reconfigure
    # Reconfigure the bootloader to add kernel command line params
    _configure_bootloader reconfigure
    # Set the bgrt theme
    plymouth-set-default-theme -R bgrt

    # Adjust the display manager to ensure flicker-free boot (ish)
    if [[ "${desktop}" == "plasma" ]]; then
      systemctl disable sddm
      systemctl enable sddm-plymouth
    elif [[ "${desktop}" == "mate" ]] || [[ "${desktop}" == "xfce" ]]; then
      systemctl disable lightdm
      systemctl enable lightdm-plymouth
    fi

    # Add the Arch Linux logo
    cp /usr/share/plymouth/arch-logo.png /usr/share/plymouth/themes/spinner/watermark.png
  fi
}

_cleanup() {
  _info "Cleaning up build user and sudo config"
  rm -rf /etc/sudoers.d/99-architect-build
  userdel -rf architect
}

_main