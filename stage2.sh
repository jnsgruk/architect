#!/bin/bash

_main() {
  # Source common fuctions to be used throughout
  # shellcheck source=architect.sh
  source /architect/architect.sh
  
  _set_locale
  _set_hostname

  _setup_mkinitcpio initial
  _setup_swap
  
  _configure_bootloader initial
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
  # Set the default console font
  echo "FONT=ter-u22n" >> /etc/vconsole.conf
  setfont ter-u22n
}

_set_hostname() {
  _info "Configuring hostname"
  local hostname
  hostname="$(_config_value hostname)"
  echo "${hostname}" > /etc/hostname
  # Update the template hosts file with selected hostname
  sed -e "s/:HOSTNAME:/${hostname}/g" /architect/templates/hosts > /etc/hosts
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
  local encrypted=""
  encrypted="$(_config_value partitioning.encrypted)"
  
  # If we're setting up disk encryption on a BIOS system
  if [[ "${encrypted}" == "true" ]] && ! _check_efi; then
    # Set variable pointing to the keyfile
    initramfs_files="/root/cryptlvm.keyfile"
    # Create a keyfile to embed in the initramfs
    _create_encryption_keyfile
  fi

  # Add basic hooks required by all installs
  hooks+=(base systemd)
  
  # If this function is passed an argument "reconfigure"
  if [[ "$1" == "reconfigure" ]]; then
    # This is only called in this mode from Stage 3 onwards to reconfigure for additional functionality
    # Check if Plymouth was enabled in the config
    if [[ "$(_config_value provisioning.plymouth)" == "true" ]]; then
      # Add the sd-plymouth hook
      hooks+=(sd-plymouth)
    fi
  fi
  
  hooks+=(autodetect)
  # If encryption is enabled, add the relevant systemd/keyboard hooks
  if [[ "${encrypted}" == "true" ]]; then
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
  hook_string="${hooks[*]}"
  sed -e "s|:FILES:|${initramfs_files}|g" \
    -e "s|:HOOKS:|${hook_string// /\ }|g" \
    /architect/templates/mkinitcpio.conf > /etc/mkinitcpio.conf

  # Regenerate the initramfs
  mkinitcpio -p linux
  # Ensure permissions are set on the initramfs to protect keyfile if present
  chmod 600 /boot/initramfs-linux*
}

_setup_swap() {
  # Setup some variables
  local swap=""
  local filesystem=""
  swap="$(_config_value partitioning.swap)"
  filesystem="$(_config_value partitioning.filesystem)"
  # Check that configured swap size is > 0
  if [[ "${swap}" -gt 0 ]]; then
    _info "Configuring swapfile"
    # Create the /swap directory if it doesn't already exist
    mkdir -p /.swap
    # Swapfile creation for btrfs is slightly different - so check
    if [[ "${filesystem}" == "ext4" ]]; then
      # Create a simple blank swapfile with dd
      dd if=/dev/zero of=/.swap/swapfile bs=1M count="${swap}" status=progress
    elif [[ "${filesystem}" == "btrfs" ]]; then
      # Setup swapfile for btrfs
      truncate -s 0 /.swap/swapfile
      # Set NoCoW attribute
      chattr +C /.swap/swapfile
      # Ensure compression is disabled
      btrfs property set /.swap/swapfile compression none
      # Allocate the swapfile
      fallocate --length "${swap}MiB" /.swap/swapfile
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
   # Initialise some variables to build on
  local encrypted=""
  local ucode=""
  local root_part=""
  local root_opts=""
  local cmdline_extra=""
  # Initialise variables
  encrypted="$(_config_value partitioning.encrypted)"

  # If this function is passed an argument "reconfigure"
  if [[ "$1" == "reconfigure" ]]; then
    # This is only called in this mode from Stage 3 onwards to reconfigure for additional functionality
    # Check if Plymouth was enabled in the config
    if [[ "$(_config_value provisioning.plymouth)" == "true" ]]; then
      # Add kernel command line params for plymouth
      cmdline_extra="quiet splash loglevel=3 rd.udev.log_priority=3 vt.global_cursor_default=0"
    fi
  fi

  # Check if the setup uses an encrypted disk
  if [[ "${encrypted}" == "true" ]]; then
    # Set the root partition
    root_part="rd.luks.name=$(blkid -t PARTLABEL=root -s UUID -o value)=cryptlvm root=/dev/vg/root"
  else
    root_part="root=/dev/disk/by-partlabel/root"
  fi 

  # Add subvolume config for btrfs
  if [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
    root_opts="rootflags=subvol=@"
  fi
  
  if _check_efi; then
    _info "EFI mode detected; configuring systemd-boot"
    
    # Install systemd-boot if it isn't already
    if [[ ! -f "/boot/EFI/systemd/systemd-bootx64.efi" ]]; then
      # Install systemd-boot with default options
      bootctl install
    fi

    # Add the microcode to the bootloader config if required
    if pacman -Qqe | grep -q intel-ucode; then 
      ucode="initrd  /intel-code.img"
    elif pacman -Qqe | grep -q amd-ucode; then 
      ucode="initrd  /amd-code.img"
    fi

    # Template out the bootloader config
    sed -e "s|:UCODE:|${ucode}|g" \
      -e "s|:ROOTPART:|${root_part}|g" \
      -e "s|:ROOTOPTS:|${root_opts}|g" \
      -e "s|:CMDLINE_EXTRA:|${cmdline_extra}|g" \
      /architect/templates/arch.conf > /boot/loader/entries/arch.conf
  else
    _info "BIOS mode detected; configuring GRUB"

    # Check if the setup uses an encrypted disk
    if [[ "${encrypted}" == "true" ]]; then
      # Set the root partition
      local uuid
      uuid="$(blkid -t PARTLABEL=root -s UUID -o value)"
      # Add the keyfile config to the partition config for the bootloader
      root_part="${root_part} rd.luks.key=${uuid}=/root/cryptlvm.keyfile rd.luks.options=keyfile-timeout=5s"
    fi

    # Template the UUID into the GRUB bootloader config template
    sed -e "s|:UCODE:|${ucode}|g" \
      -e "s|:ROOTPART:|${root_part}|g" \
      -e "s|:ROOTOPTS:|${root_opts}|g" \
      -e "s|:CMDLINE_EXTRA:|${cmdline_extra}|g" \
      /architect/templates/grub.default > /etc/default/grub

    grub-install --target=i386-pc --recheck "$(_config_value partitioning.disk)"
    # Generate GRUB config; microcode updates should be detected automatically
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

_setup_users() {
  # Setup and init local variable
  local username=""
  username="$(_config_value username)"
  
  _warn "Changing root password; enter below:"
  # Change the root password
  passwd
  _info "Creating a non-root user: ${username}"
  # Create a new default user
  useradd -m -s /bin/bash -G wheel "${username}"
  _warn "Enter password for ${username}"
  passwd "${username}"
  # Add user to some groups
  usermod -aG lp,storage,input "${username}"
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
  if [[ "$(cat /sys/block/"${disk:5}"/queue/rotational)" == "0" ]]; then
    systemctl enable fstrim.timer
  fi
}

if [[ "${1:-}" == "install" ]]; then
  _main
fi