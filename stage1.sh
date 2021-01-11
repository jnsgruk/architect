#!/bin/bash

pacstrap_packages=()

_main() {
  # Source some helper functions and config
  source /architect/architect.sh

  _preamble
  _partition_and_mount
  _pacstrap

  _info "Copying architect into chroot"
  cp -r /architect /mnt/architect
  cp /usr/bin/yq /mnt/usr/bin/yq

  _info "Chrooting and running stage 2"
  chmod +x /architect/stage2.sh
  arch-chroot /mnt /architect/stage2.sh

  _cleanup

  if [[ "$(_config_value architect.reboot)" == "true" ]]; then
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
  
  # luksFormat the root partition
  if _check_efi; then
    cryptsetup luksFormat "$(_config_value partitioning.disk)2"
  else
    # If we're on a BIOS system, we use GRUB, which doesn't support LUKS2
    cryptsetup luksFormat --type luks1 "$(_config_value partitioning.disk)2"
    # Add grub to the initial install, we'll use it to boot the non-uefi system
    pacstrap_packages+=(grub)
  fi
  
  _warn "Decrypting disk, password entry required"
  # Open the encrypted container
  cryptsetup open "$(_config_value partitioning.disk)2" cryptlvm
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
  # Give the first argument to this function a friendly name
  local root_part="${1}"

  if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
      # Format the root partition
    mkfs.ext4 "${root_part}"
    # Mount the root partition to /mnt
    mount "${root_part}" /mnt
  elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
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
    # Format the boot partition
    mkfs.fat -F32 "$(_config_value partitioning.disk)1"
    # Mount the boot partition
    mount -o "defaults,x-mount.mkdir" "$(_config_value partitioning.disk)1" /mnt/boot
  fi
}


_partition_and_mount() {
  _info "Partitioning disks and generating fstab"
  # Create a new partition table
  parted "$(_config_value partitioning.disk)" -s mklabel gpt
  
  # Check if we're on a UEFI system
  if _check_efi; then
    # Create a 500MiB FAT32 Boot Partition
    parted "$(_config_value partitioning.disk)" -s mkpart boot fat32 0% 500MiB
    # Set the boot/esp flags on the boot partition
    parted "$(_config_value partitioning.disk)" set 1 boot on
    # Create a single root partition
    parted "$(_config_value partitioning.disk)" -s mkpart root 500MiB 100%
  else
    # Create the BIOS boot partition
    parted "$(_config_value partitioning.disk)" -s mkpart bios 0% 2
    # Set the bios_grub flag on the boot partition
    parted "$(_config_value partitioning.disk)" set 1 bios_grub on
    # Create a single root partition
    parted "$(_config_value partitioning.disk)" -s mkpart root 2 100%
    # Set the boot flag on the root partition
    parted "$(_config_value partitioning.disk)" set 2 boot on
  fi
  
  # Check if the config enforces disk encryption
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Setup the LUKS/LVM containers
    _setup_luks_lvm
    root_part="/dev/vg/root"
  else
    root_part="$(_config_value partitioning.disk)2"
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
  # Configure pacman to use color in output
  sed -i "s/#Color/Color/g" /etc/pacman.conf
  # Add basic required packages to pacstrap
  pacstrap_packages+=(base linux linux-firmware sudo networkmanager)
  
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
}

_cleanup() {
  _info "Cleaning up"
  rm -rf /mnt/architect
  rm /usr/bin/yq
}

_main