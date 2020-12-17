#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  
  _set_locale
  _set_hostname
  _misc_config

  _install_microcode
  _install_bootloader
  _setup_boot
  _setup_users
}

_set_locale() {
  _info "Setup locale details and timezone"
  # Setup the timezone
  ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  hwclock --systohc
  # Uncomment the selected locale from the locale.gen file
  sed -i "s/#${LOCALE}/${LOCALE}/g" /etc/locale.gen
  # Regenerate the locales
  locale-gen
  # Set the default language and keymaps
  echo "LANG=${LOCALE}" > /etc/locale.conf
  echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
}

_set_hostname() {
  _info "Configuring hostname"
  echo "${NEWHOSTNAME}" > /etc/hostname
  # Update the template hosts file with selected hostname
  sed -e "s/:HOSTNAME:/${NEWHOSTNAME}/g" /architect/templates/hosts > /etc/hosts
}

_misc_config() {
  # Configure pacman to use color in output
  sed -i "s/#Color/Color/g" /etc/pacman.conf
}

_install_microcode() {
  if systemd-detect-virt; then
    _info "Virtualisation detected, skipping ucode installation"
  elif grep -q "GenuineIntel" /proc/cpuinfo; then
    _info "Intel CPU detected, installing intel-ucode"
    pacman -S --noconfirm intel-ucode
  elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    _info "AMD CPU detected, installing amd-ucode"
    pacman -S --noconfirm amd-ucode
  fi
}

_install_bootloader() {
  if _check_efi; then
    _info "EFI mode detected; installing and configuring systemd-boot"
    # Install systemd-boot with default options
    bootctl install
    # Get the template bootloader config
    cp /architect/templates/arch.conf /boot/loader/entries/arch.conf
    # Add the microcode to the bootloader config if required
    if pacman -Qqe | grep -q intel-ucode; then 
      sed -i '2 a initrd  /intel-code.img' /boot/loader/entries/arch.conf
    elif pacman -Qqe | grep -q amd-ucode; then 
      sed -i '2 a initrd  /amd-code.img' /boot/loader/entries/arch.conf
    fi
  else
    _info "BIOS mode detected; installing and configuring GRUB"
    # Install grub
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "${DISK}"
    # Generate GRUB config; microcode updates should be detected automatically
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

_setup_users() {
  _warn "Changing root password; enter below:"
  # Change the root password
  passwd
  _info "Creating a non-root user: ${NEWUSER}"
  # Create a new default user
  useradd -m -s /bin/bash -G wheel "${NEWUSER}"
  _warn "Enter password for ${NEWUSER}"
  passwd "${NEWUSER}"
  # Uncomment a line from the /etc/sudoers file
  _info "Configuring sudo access for the wheel group"
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /etc/sudoers
}

_setup_boot() {
  _info "Enabling NetworkManager"
  systemctl enable NetworkManager
}

_main