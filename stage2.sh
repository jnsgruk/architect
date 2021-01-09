#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  
  _set_locale
  _set_hostname
  _misc_config

  _setup_mkinitcpio
  _setup_swap
  
  _install_microcode
  _install_bootloader
  _setup_boot
  _setup_users

  # Check if stage 3 is enabled
  if [[ "$(_config_value architect.disable_stage3)" != "true" ]]; then
    # Run stage 3 for additional packages and customisation
    /bin/bash /architect/stage3.sh
  fi
}

_set_locale() {
  _info "Setup locale details and timezone"
  # Setup the timezone
  ln -sf "/usr/share/zoneinfo/$(_config_value regional.timezone)" /etc/localtime
  hwclock --systohc
  # Uncomment the selected locale from the locale.gen file
  sed -i "s/#$(_config_value regional.locale)/$(_config_value regional.locale)/g" /etc/locale.gen
  # Regenerate the locales
  locale-gen
  # Set the default language and keymaps
  echo "LANG=$(_config_value regional.locale)" > /etc/locale.conf
  echo "KEYMAP=$(_config_value regional.keymap)" > /etc/vconsole.conf
}

_set_hostname() {
  _info "Configuring hostname"
  echo "$(_config_value hostname)" > /etc/hostname
  # Update the template hosts file with selected hostname
  sed -e "s/:HOSTNAME:/$(_config_value hostname)/g" /architect/templates/hosts > /etc/hosts
}

_misc_config() {
  # Configure pacman to use color in output
  sed -i "s/#Color/Color/g" /etc/pacman.conf
}

_setup_mkinitcpio() {
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Install the necessary utilities
    pacman -S --noconfirm lvm2
    if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
      if _check_efi; then
        # Copy across the modified mkinitcpio.conf
        cp /architect/templates/mkinitcpio_encrypted_ext4.conf /etc/mkinitcpio.conf
      else
        # Copy across the modified mkinitcpio.conf
        cp /architect/templates/mkinitcpio_encrypted_ext4_grub.conf /etc/mkinitcpio.conf
        # Generate a new keyfile for the luks partition
        dd bs=512 count=4 if=/dev/random of=/root/cryptlvm.keyfile iflag=fullblock
        # Set permissions on keyfile
        chmod 000 /root/cryptlvm.keyfile
        # Add the keyfile to luks
        _warn "Adding a keyfile to LUKS to avoid double password entry on boot. Enter disk encryption password when prompted"
        cryptsetup -v luksAddKey "$(_config_value partitioning.disk)2" /root/cryptlvm.keyfile
      fi
    elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
      # Copy across the modified mkinitcpio.conf
      cp /architect/templates/mkinitcpio_encrypted_btrfs.conf /etc/mkinitcpio.conf
    fi
  else
    if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
      # Copy across the modified mkinitcpio.conf
      cp /architect/templates/mkinitcpio_ext4.conf /etc/mkinitcpio.conf
    elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
      # Copy across the modified mkinitcpio.conf
      cp /architect/templates/mkinitcpio_btrfs.conf /etc/mkinitcpio.conf
    fi
  fi
  # Regenerate the initramfs
  mkinitcpio -p linux
  # Ensure permissions are set on the initramfs to protect keyfile if present
  chmod 600 /boot/initramfs-linux*
}

_setup_swap() {
  # Check that configured swap size is > 0
  if [[ "$(_config_value partitioning.swap)" -gt 0 ]]; then
    _info "Configuring swapfile"
    # Create the /swap directory if it doesn't already exist
    mkdir -p /.swap
    # Swapfile creation for btrfs is slightly different - so check
    if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
      dd if=/dev/zero of=/.swap/swapfile bs=1M count="$(_config_value partitioning.swap)" status=progress
    elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
      # Setup swapfile for btrfs
      truncate -s 0 /.swap/swapfile
      # Set NoCoW attribute
      chattr +C /.swap/swapfile
      # Ensure compression is disabled
      btrfs property set /.swap/swapfile compression none
      # Allocate the swapfile
      fallocate --length "$(_config_value partitioning.swap)MiB" /.swap/swapfile
    fi

    # Set swapfile permissions
    chmod 600 /.swap/swapfile
    # Make the swapfile
    mkswap /.swap/swapfile
    # Write an entry into the fstab to activate swap on boot
    echo "/.swap/swapfile  none  swap  defaults  0 0" >> /etc/fstab
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
    if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
      if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
        # Get the UUID of the root partition
        root_uuid="$(blkid -t PARTLABEL=root -s UUID -o value)"
        # Add the options line to the systemd-boot config
        echo "options rd.luks.name=$root_uuid=cryptlvm root=/dev/vg/root" >> /boot/loader/entries/arch.conf
      elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
        _error "Not implemented"
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
    if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
      # Get the UUID of the root partition
      root_uuid="$(blkid -t PARTLABEL=root -s UUID -o value)"
      # Template the UUID into the GRUB bootloader config template
      sed "s/:UUID:/${root_uuid}/g" /architect/templates/grub.default > /etc/default/grub
    fi

    grub-install --target=i386-pc --recheck "$(_config_value partitioning.disk)"
    # Generate GRUB config; microcode updates should be detected automatically
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

_setup_users() {
  _warn "Changing root password; enter below:"
  # Change the root password
  passwd
  _info "Creating a non-root user: $(_config_value username)"
  # Create a new default user
  useradd -m -s /bin/bash -G wheel "$(_config_value username)"
  _warn "Enter password for $(_config_value username)"
  passwd "$(_config_value username)"
  # Uncomment a line from the /etc/sudoers file
  _info "Configuring sudo access for the wheel group"
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /etc/sudoers
}

_setup_boot() {
  _info "Enabling NetworkManager"
  systemctl enable NetworkManager
}

_main