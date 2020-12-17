#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  
  _set_locale
  _set_hostname
  _misc_config

  _setup_mkinitcpio
  
  _install_microcode
  _install_bootloader
  _setup_boot
  _setup_users

  # Check if stage 3 is enabled
  if [[ -z "${DISABLE_STAGE3}" ]]; then
    # Run stage 3 for additional packages and customisation
    /bin/bash /architect/stage3.sh
  fi
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

_setup_mkinitcpio() {
  if [[ "${ENCRYPTED}" == "true" ]]; then
    # Install the necessary utilities
    pacman -S --noconfirm lvm2
    if [[ "${FILESYSTEM}" == "ext4" ]]; then
      # Copy across the modified mkinitcpio.conf
      cp /architect/templates/mkinitcpio_encrypted_ext4.conf /etc/mkinitcpio.conf
    elif [[ "${FILESYSTEM}" == "btrfs" ]]; then
      # Copy across the modified mkinitcpio.conf
      cp /architect/templates/mkinitcpio_encrypted_btrfs.conf /etc/mkinitcpio.conf
    fi
    # Regenerate the initramfs
    mkinitcpio -p linux
  fi
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
    # Start building the bootloader config
    echo "title   Arch Linux" > /boot/loader/entries/arch.conf
    echo "linux   /vmlinuz-linux" >> /boot/loader/entries/arch.conf
    
    # Add the microcode to the bootloader config if required
    if pacman -Qqe | grep -q intel-ucode; then 
      echo "initrd  /intel-code.img" >> /boot/loader/entries/arch.conf
    elif pacman -Qqe | grep -q amd-ucode; then 
      echo "initrd  /amd-code.img" >> /boot/loader/entries/arch.conf
    fi
    
    # Add the initramfs to the bootloader config
    echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
    
    # Check if the setup uses an encrypted disk
    if [[ "${ENCRYPTED}" == "true" ]]; then
      if [[ "${FILESYSTEM}" == "ext4" ]]; then
        # Add a line to the bootloader config
        echo "options cryptdevice=/dev/disk/by-partlabel/root:cryptlvm root=/dev/vg/root rw" >> /boot/loader/entries/arch.conf
      elif [[ "${FILESYSTEM}" == "btrfs" ]]; then
        _error "Not implmented"
      fi
    else
      # Add the standard boot line to the bootloader if not encrypted
      echo "options root=/dev/disk/by-partlabel/root rw" >> /boot/loader/entries/arch.conf
    fi
  else
    _info "BIOS mode detected; installing and configuring GRUB"
    # Install grub
    pacman -S --noconfirm grub

    # If encrypted, then copy our modified grub defaults
    if [[ "${ENCRYPTED}" == "true" ]]; then
      cp /architect/templates/grub.default /etc/default/grub
    fi

    grub-install --target=i386-pc --recheck "${DISK}"
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