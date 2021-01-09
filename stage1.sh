#!/bin/bash

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

  _info "Rebooting"
  umount -R /mnt
  reboot 0
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
}

_partition_uefi_ext4() {
  # Create a 500MiB FAT32 Boot Partition
  parted "$(_config_value partitioning.disk)" -s mkpart boot fat32 0% 500MiB
  # Set the boot/esp flags on the boot partition
  parted "$(_config_value partitioning.disk)" set 1 boot on
  # Create a single ext4 root partition
  parted "$(_config_value partitioning.disk)" -s mkpart root ext4 500MiB 100%
  # Format the boot partition
  mkfs.fat -F32 "$(_config_value partitioning.disk)1"
  
  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Setup the LUKS/LVM containers
    _setup_luks_lvm
    root_part="/dev/vg/root"
  else
    root_part="$(_config_value partitioning.disk)2"
  fi
  
  # Format the root partition
  mkfs.ext4 "${root_part}"
  # Mount the root partition to /mnt
  mount "${root_part}" /mnt
  # Create the mount point for boot
  mkdir -p /mnt/boot
  # Mount the boot partition
  mount "$(_config_value partitioning.disk)1" /mnt/boot
}

_partition_bios_ext4() {
  # Create the BIOS boot partition
  parted "$(_config_value partitioning.disk)" -s mkpart bios 0% 2
  # Set the bios_grub flag on the boot partition
  parted "$(_config_value partitioning.disk)" set 1 bios_grub on
  # Create a single ext4 root partition
  parted "$(_config_value partitioning.disk)" -s mkpart root 2 100%
  # Set the boot flag on the root partition
  parted "$(_config_value partitioning.disk)" set 2 boot on

  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Setup the LUKS/LVM containers
    _setup_luks_lvm
    root_part="/dev/vg/root"
  else
    root_part="$(_config_value partitioning.disk)2"
  fi

  # Format the root partition
  mkfs.ext4 "${root_part}"
  # Mount the root partition to /mnt
  mount "${root_part}" /mnt
}

_partition_bios_btrfs() {
  # Create the BIOS boot partition
  parted "$(_config_value partitioning.disk)" -s mkpart bios 0% 2
  # Set the bios_grub flag on the boot partition
  parted "$(_config_value partitioning.disk)" set 1 bios_grub on
  # Create a single ext4 root partition
  parted "$(_config_value partitioning.disk)" -s mkpart root 2 100%
  # Set the boot flag on the root partition
  parted "$(_config_value partitioning.disk)" set 2 boot on

  if [[ "$(_config_value partitioning.encrypted)" == "true" ]]; then
    # Setup the LUKS/LVM containers
    _setup_luks_lvm
    root_part="/dev/vg/root"
  else
    root_part="$(_config_value partitioning.disk)2"
  fi

  # Format the root partition
  mkfs.btrfs --force "${root_part}"
  # Mount the root partition to /mnt
  mount "${root_part}" /mnt
  # Create btrfs subvolumes
  btrfs subvolume create /mnt/root
  btrfs subvolume create /mnt/home
  btrfs subvolume create /mnt/snapshots
  btrfs subvolume create /mnt/swap
  btrfs subvolume create /mnt/var
  # Remount with btrfs options
  umount -R /mnt
  btrfs_opts="defaults,x-mount.mkdir,compress=lzo,ssd,noatime,discard=async"
  mount -t btrfs -o subvol=root,"${btrfs_opts}" "${root_part}" /mnt
  mount -t btrfs -o subvol=home,"${btrfs_opts}" "${root_part}" /mnt/home
  mount -t btrfs -o subvol=var,"${btrfs_opts}" "${root_part}" /mnt/var
  mount -t btrfs -o subvol=swap,defaults "${root_part}" /mnt/.swap
  mount -t btrfs -o subvol=snapshots,"${btrfs_opts}" "${root_part}" /mnt/.snapshots
}

_partition_and_mount() {
  _info "Partitioning disks and generating fstab"
  # Create a new partition table
  parted "$(_config_value partitioning.disk)" -s mklabel gpt

  if [[ "$(_config_value partitioning.filesystem)" == "ext4" ]]; then
    # Check if we're on a BIOS/UEFI system
    if _check_efi; then
      _partition_uefi_ext4
    else
      _partition_bios_ext4
    fi
  elif [[ "$(_config_value partitioning.filesystem)" == "btrfs" ]]; then
    # Check if we're on a BIOS/UEFI system
    if _check_efi; then
      _partition_uefi_btrfs
    else
      _partition_bios_btrfs
    fi
  fi
  
  # Create the etc directory
  mkdir /mnt/etc
  # Generate the fstab file
  genfstab -U /mnt >> /mnt/etc/fstab
}

_pacstrap() {
  pacstrap_packages=(base linux linux-firmware sudo networkmanager btrfs-progs)
  # Pacstrap the system with the base packages above
  _info "Bootstrapping baseline Arch Linux system"
  pacstrap /mnt "${pacstrap_packages[@]}"
}

_cleanup() {
  _info "Cleaning up"
  rm -rf /mnt/architect
  rm /usr/bin/yq
}

_main