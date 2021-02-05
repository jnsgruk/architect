#!/bin/bash

# Array to be built up appropriately as options are parsed
pacstrap_packages=()

_main() {
  # Source some helper functions and config
  # shellcheck source=architect.sh
  source /architect/architect.sh

  _preamble
  _partition_and_mount
  _pacstrap

  _info "Copying architect into chroot"
  cp -r /architect /mnt/architect
  cp /usr/bin/yq /mnt/usr/bin/yq

  _info "Chrooting and running stage 2"
  chmod +x /architect/stage2.sh
  arch-chroot /mnt /architect/stage2.sh install

  _cleanup

  if [[ "${ARCHITECT_REBOOT}" == "true" ]]; then
    _info "Rebooting"
    umount -R /mnt
    reboot 0
  fi
}

_preamble() {
  _info "Setting up keyboard layout and timezone"
  # Load a keymap based on env variable, default to uk
  loadkeys "$(_config_value regional.keymap)"
  # Enable ntp
  timedatectl set-ntp true
}

_setup_luks_lvm() {
  _warn "Setting up disk encryption. Confirmation and password entry required"
  local disk=""
  local boot_part="1"
  local root_part="2"
  disk="$(_config_value partitioning.disk)"
  
  # Handle nvme partition names
  if echo "${disk}" | grep -q "nvme"; then
    root_part="p2"
    boot_part="p1"
  fi
  
  # luksFormat the root partition
  if _check_efi; then
    cryptsetup luksFormat "${disk}${root_part}"
  else
    # If we're on a BIOS system, we use GRUB, which doesn't support LUKS2
    cryptsetup luksFormat --type luks1 "${disk}${root_part}"
  fi
  
  _warn "Decrypting disk, password entry required"
  # Open the encrypted container
  cryptsetup open "${disk}${root_part}" cryptlvm
  # Setup LVM physical volumes, volume groups and logical volumes
  _info "Setting up LVM"
  # Create a physical volume
  pvcreate /dev/mapper/cryptlvm
  vgcreate vg /dev/mapper/cryptlvm
  lvcreate -l 100%FREE vg -n root

  # Add the lvm2 package to the new install list
  pacstrap_packages+=(lvm2)
}

_create_and_mount_filesystems() {
  # Declare and initialise some local vars
  local root_part=""
  local filesystem=""
  local disk=""
  root_part="${1}"
  filesystem="$(_config_value partitioning.filesystem)"
  disk="$(_config_value partitioning.disk)"

  if [[ "${filesystem}" == "ext4" ]]; then
      # Format the root partition
    mkfs.ext4 "${root_part}"
    # Mount the root partition to /mnt
    mount "${root_part}" /mnt
  elif [[ "${filesystem}" == "btrfs" ]]; then
    # Add the btrfs-progs to the new install list
    pacstrap_packages+=(btrfs-progs)
    # Format the root partition
    mkfs.btrfs --force "${root_part}"
    # Mount the root partition to /mnt
    mount "${root_part}" /mnt
    # Create btrfs subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@var
    # Remount with btrfs options
    umount -R /mnt
    btrfs_opts="defaults,x-mount.mkdir,compress=lzo,ssd,noatime,nodiratime"
    mount -t btrfs -o subvol=@,"${btrfs_opts}" "${root_part}" /mnt
    mount -t btrfs -o subvol=@home,"${btrfs_opts}" "${root_part}" /mnt/home
    mount -t btrfs -o subvol=@var,"${btrfs_opts}" "${root_part}" /mnt/var
    mount -t btrfs -o subvol=@snapshots,"${btrfs_opts}" "${root_part}" /mnt/.snapshots
    mount -t btrfs -o subvol=@swap,defaults,x-mount.mkdir "${root_part}" /mnt/.swap
  fi

  # Check if we're on a UEFI system
  if _check_efi; then
    local boot_part="${disk}1"
    # Handle nvme partition names
    if echo "${disk}" | grep -q "nvme"; then
      boot_part="${disk}p1"
    fi
    # Format the boot partition
    mkfs.fat -F32 "${boot_part}"
    # Mount the boot partition
    mount -o "defaults,x-mount.mkdir" "${boot_part}" /mnt/boot
  fi
}


_partition_and_mount() {
  _info "Partitioning disks and generating fstab"
  local disk=""
  local root_part=""
  
  disk="$(_config_value partitioning.disk)"
  # Create a new partition table
  parted "${disk}" -s mklabel gpt
  
  # Check if we're on a UEFI system
  if _check_efi; then
    # Create a 500MiB FAT32 Boot Partition
    parted "${disk}" -s mkpart boot fat32 0% 500MiB
    # Set the boot/esp flags on the boot partition
    parted "${disk}" set 1 boot on
    # Create a single root partition
    parted "${disk}" -s mkpart root 500MiB 100%
  else
    # Create the BIOS boot partition
    parted "${disk}" -s mkpart bios 0% 2
    # Set the bios_grub flag on the boot partition
    parted "${disk}" set 1 bios_grub on
    # Create a single root partition
    parted "${disk}" -s mkpart root 2 100%
    # Set the boot flag on the root partition
    parted "${disk}" set 2 boot on
  fi
  
  # Check if the config enforces disk encryption
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Setup the LUKS/LVM containers
    _setup_luks_lvm
    root_part="/dev/vg/root"
  else
    # Handle nvme partition names
    if echo "${disk}" | grep -q "nvme"; then
      root_part="${disk}p2"
    else
      root_part="${disk}2"
    fi
  fi

  # Create the relevant filesystems and mount them for install using the newly
  # created root partition
  _create_and_mount_filesystems "${root_part}"
  # Create the etc directory
  mkdir /mnt/etc
  # Generate the fstab file
  genfstab -U /mnt >> /mnt/etc/fstab
}

_pacstrap() {
  # Add basic required packages to pacstrap
  pacstrap_packages+=(base linux linux-firmware sudo networkmanager vim curl htop wget man-db terminus-font)

  # Check if we're in a BIOS system
  if ! _check_efi; then
    # Add grub to the initial install, we'll use it to boot the non-uefi system
    pacstrap_packages+=(grub)
  fi
  
  # Work out the CPU model and add ucode to pacstrap if required
  if systemd-detect-virt; then
    _info "Virtualisation detected, skipping ucode installation"
  elif grep -q "GenuineIntel" /proc/cpuinfo; then
    _info "Intel CPU detected, installing intel-ucode"
    pacstrap_packages+=(intel-ucode)
  elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    _info "AMD CPU detected, installing amd-ucode"
    pacstrap_packages+=(amd-ucode)
  fi
  
  # Pacstrap the system with the required packages
  _info "Bootstrapping baseline Arch Linux system"
  pacstrap /mnt "${pacstrap_packages[@]}"
  
  # Configure Pacman in new install
  sed -i "s/#Color/Color/g" /mnt/etc/pacman.conf
  sed -i "/^Color/a ILoveCandy" /mnt/etc/pacman.conf
}

_cleanup() {
  _info "Cleaning up"
  # Read the  reboot config var before removing yq
  if [[ "$(_config_value architect.reboot)" == "true" ]]; then
    ARCHITECT_REBOOT="true"
    export ARCHITECT_REBOOT
  fi
  # Cleanup files
  rm -rf /mnt/architect
  rm /usr/bin/yq
}

_main