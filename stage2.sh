#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  source /architect/architect.sh
  
  _set_locale
  _set_hostname

  _setup_mkinitcpio
  _setup_swap
  
  _configure_bootloader
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

_create_encryption_keyfile() {
  # Generate a new keyfile for the luks partition
  dd bs=512 count=4 if=/dev/random of=/root/cryptlvm.keyfile iflag=fullblock
  # Set permissions on keyfile
  chmod 000 /root/cryptlvm.keyfile
  # Add the keyfile to luks
  _warn "Adding a keyfile to LUKS to avoid double password entry on boot. Enter disk encryption password when prompted"
  cryptsetup -v luksAddKey "$(_config_value partitioning.disk)2" /root/cryptlvm.keyfile
}

_setup_mkinitcpio() {
  # Setup some variables
  local initramfs_files=""
  local hooks=()
  
  # If we're setting up disk encryption on a BIOS system
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]] && ! _check_uefi; then
    # Set variable pointing to the keyfile
    initramfs_files="/root/cryptlvm.keyfile"
    # Create a keyfile to embed in the initramfs
    _create_encryption_keyfile
  fi

  # Add basic hooks required by all installs
  hooks+=(base systemd autodetect)
  # If encryption is enabled, add the relevant systemd/keyboard hooks
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    hooks+=(keyboard sd-vconsole modconf block sd-encrypt sd-lvm2 filesystems)
  else
    # Standard hooks without encryption
    hooks+=(modconf block filesystems)
  fi
  # Check if we're installing on btrfs
  if [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
    hooks+=(btrfs)
  fi
  # Add the fsck hook last
  hooks+=(fsck)

  # Template out a new mkinitcpio config
  hook_string="${hooks[@]}"
  sed -e "s|:FILES:|${initramfs_files}|g" \
    -e "s|:HOOKS:|${hook_string// /\ }|g" \
    /architect/templates/mkinitcpio.conf > mkinitcpio.conf

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
      # Create a simple blank swapfile with dd
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

_configure_bootloader() {
  if _check_efi; then
    _info "EFI mode detected; installing and configuring systemd-boot"
    # Install systemd-boot with default options
    bootctl install

    # Initialise some variables to build on
    local ucode=""
    local root_part=""
    local root_opts=""
    local cmdline_extra=""
    
    # Add the microcode to the bootloader config if required
    if pacman -Qqe | grep -q intel-ucode; then 
      ucode="initrd  /intel-code.img"
    elif pacman -Qqe | grep -q amd-ucode; then 
      ucode="initrd  /amd-code.img"
    fi
        
    # Check if the setup uses an encrypted disk
    if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
      # Set the root partition
      root_part="rd.luks.name=$(blkid -t PARTLABEL=root -s UUID -o value)=cryptlvm root=/dev/vg/root"
    else
      root_part="root=/dev/disk/by-partlabel/root"
    fi  

    # Add subvolume config for btrfs
    if [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
      root_opts="rootflags=subvol=@"
    fi

    sed -e "s|:UCODE:|${ucode}|g" \
      -e "s|:ROOTPART:|${root_part}|g" \
      -e "s|:ROOTOPTS:|${root_opts}|g" \
      -e "s|:CMDLINE_EXTRA:|${cmdline_extra}|g" \
      /architect/templates/arch.conf > /boot/loader/entries/arch.conf
  else
    _info "BIOS mode detected; configuring GRUB"

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
  # Enable NetworkManager start on boot
  _info "Enabling NetworkManager"
  systemctl enable NetworkManager
  # Get the full /dev/xxx name of the disk
  disk="$(_config_value partitioning.disk)"
  # Enable fstrim timer if the boot disk is an SSD (strip the /dev/ from the disk name)
  if [[ "$(cat /sys/block/${disk:5}/queue/rotational)" == "0" ]]; then
    systemctl enable fstrim.timer
  fi
}

_main